use std::time::Instant;

use crate::{cruby::*, options::get_option, state::{zjit_enabled_p, ZJITState}};

macro_rules! make_counters {
    (
        default {
            $($default_counter_name:ident,)+
        }
        $($counter_name:ident,)+
    ) => {
        /// Struct containing the counter values
        #[derive(Default, Debug)]
        pub struct Counters {
            $(pub $default_counter_name: u64,)+
            $(pub $counter_name: u64,)+
        }

        /// Enum to represent a counter
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, PartialEq, Eq, Debug)]
        pub enum Counter {
            $($default_counter_name,)+
            $($counter_name,)+
        }

        impl Counter {
            pub fn name(&self) -> String {
                match self {
                    $( Counter::$default_counter_name => stringify!($default_counter_name).to_string(), )+
                    $( Counter::$counter_name => stringify!($counter_name).to_string(), )+
                }
            }
        }

        /// Map a counter to a pointer
        pub fn counter_ptr(counter: Counter) -> *mut u64 {
            let counters = $crate::state::ZJITState::get_counters();
            match counter {
                $( Counter::$default_counter_name => std::ptr::addr_of_mut!(counters.$default_counter_name), )+
                $( Counter::$counter_name => std::ptr::addr_of_mut!(counters.$counter_name), )+
            }
        }

        /// List of counters that are available without --zjit-stats.
        /// They are incremented only by `incr_counter()` and don't use `gen_incr_counter()`.
        pub const DEFAULT_COUNTERS: &'static [Counter] = &[
            $( Counter::$default_counter_name, )+
        ];

        /// List of all counters
        pub const ALL_COUNTERS: &'static [Counter] = &[
            $( Counter::$default_counter_name, )+
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

    // The number of times YARV instructions are executed on JIT code
    zjit_insn_count,

    // failed_: Compilation failure reasons
    failed_iseq_stack_too_large,
    failed_hir_compile,
    failed_hir_compile_validate,
    failed_hir_optimize,
    failed_asm_compile,

    // exit_: Side exit reasons (ExitCounters shares the same prefix)
    exit_compilation_failure,
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

/// Return a raw pointer to the exit counter for the YARV instruction at a given PC
pub fn exit_counter_ptr(pc: *const VALUE) -> *mut u64 {
    let opcode = unsafe { rb_vm_insn_addr2opcode((*pc).as_ptr()) };
    let exit_counters = ZJITState::get_exit_counters();
    unsafe { exit_counters.get_unchecked_mut(opcode as usize) }
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
            // Evaluate $value only when it's needed
            if key == target_key {
                return VALUE::fixnum_from_usize($value as usize);
            } else if $hash != Qnil {
                #[allow(unused_unsafe)]
                unsafe { rb_hash_aset($hash, key, VALUE::fixnum_from_usize($value as usize)); }
            }
        }
    }

    let hash = if target_key.nil_p() {
        unsafe { rb_hash_new() }
    } else {
        Qnil
    };

    // If not --zjit-stats, set only default counters
    if !get_option!(stats) {
        for &counter in DEFAULT_COUNTERS {
            set_stat!(hash, &counter.name(), unsafe { *counter_ptr(counter) });
        }
        return hash;
    }

    // Set all counters for --zjit-stats
    for &counter in ALL_COUNTERS {
        set_stat!(hash, &counter.name(), unsafe { *counter_ptr(counter) });
    }

    // Set side exit stats
    let exit_counters = ZJITState::get_exit_counters();
    let mut side_exit_count = 0;
    for op_idx in 0..VM_INSTRUCTION_SIZE as usize {
        let op_name = insn_name(op_idx);
        let key_string = "exit_".to_owned() + &op_name;
        let count = exit_counters[op_idx];
        side_exit_count += count;
        set_stat!(hash, &key_string, count);
    }
    set_stat!(hash, "side_exit_count", side_exit_count);

    if unsafe { rb_vm_insn_count } > 0 {
        set_stat!(hash, "vm_insn_count", unsafe { rb_vm_insn_count });
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
