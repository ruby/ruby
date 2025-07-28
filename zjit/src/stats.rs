// Maxime would like to rebuild an improved stats system
// Individual stats should be tagged as always available, or only available in stats mode
// We could also tag which stats are fallback or exit counters, etc. Maybe even tag units?
//
// Comptime vs Runtime stats?

use crate::{cruby::*, options::get_option, state::{zjit_enabled_p, ZJITState}};

macro_rules! make_counters {
    ($($counter_name:ident,)+) => {
        /// Struct containing the counter values
        #[derive(Default, Debug)]
        pub struct Counters { $(pub $counter_name: u64),+ }

        /// Enum to represent a counter
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, PartialEq, Eq, Debug)]
        pub enum Counter { $($counter_name),+ }

        /// Map a counter to a pointer
        pub fn counter_ptr(counter: Counter) -> *mut u64 {
            let counters = $crate::state::ZJITState::get_counters();
            match counter {
                $( Counter::$counter_name => std::ptr::addr_of_mut!(counters.$counter_name) ),+
            }
        }
    }
}

// Declare all the counters we track
make_counters! {
    // The number of times YARV instructions are executed on JIT code
    zjit_insns_count,
}

pub fn zjit_alloc_size() -> usize {
    0 // TODO: report the actual memory usage
}

/// Return a Hash object that contains ZJIT statistics
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_stats(_ec: EcPtr, _self: VALUE) -> VALUE {
    if !zjit_enabled_p() {
        return Qnil;
    }

    fn set_stat(hash: VALUE, key: &str, value: u64) {
        unsafe { rb_hash_aset(hash, rust_str_to_sym(key), VALUE::fixnum_from_usize(value as usize)); }
    }

    let hash = unsafe { rb_hash_new() };
    // TODO: Set counters that are always available here

    // Set counters that are enabled when --zjit-stats is enabled
    if get_option!(stats) {
        let counters = ZJITState::get_counters();
        set_stat(hash, "zjit_insns_count", counters.zjit_insns_count);
        set_stat(hash, "vm_insns_count", unsafe { rb_vm_insns_count });
    }

    hash
}
