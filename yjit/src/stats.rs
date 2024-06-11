//! Everything related to the collection of runtime stats in YJIT
//! See the stats feature and the --yjit-stats command-line option

#![allow(dead_code)] // Counters are only used with the stats features

use std::alloc::{GlobalAlloc, Layout, System};
use std::ptr::addr_of_mut;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;
use std::collections::HashMap;

use crate::codegen::CodegenGlobals;
use crate::cruby::*;
use crate::options::*;
use crate::yjit::yjit_enabled_p;

/// Running total of how many ISeqs are in the system.
#[no_mangle]
pub static mut rb_yjit_live_iseq_count: u64 = 0;

/// Monotonically increasing total of how many ISEQs were allocated
#[no_mangle]
pub static mut rb_yjit_iseq_alloc_count: u64 = 0;

/// A middleware to count Rust-allocated bytes as yjit_alloc_size.
#[global_allocator]
static GLOBAL_ALLOCATOR: StatsAlloc = StatsAlloc { alloc_size: AtomicUsize::new(0) };

pub struct StatsAlloc {
    alloc_size: AtomicUsize,
}

unsafe impl GlobalAlloc for StatsAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        self.alloc_size.fetch_add(layout.size(), Ordering::SeqCst);
        System.alloc(layout)
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        self.alloc_size.fetch_sub(layout.size(), Ordering::SeqCst);
        System.dealloc(ptr, layout)
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        self.alloc_size.fetch_add(layout.size(), Ordering::SeqCst);
        System.alloc_zeroed(layout)
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if new_size > layout.size() {
            self.alloc_size.fetch_add(new_size - layout.size(), Ordering::SeqCst);
        } else if new_size < layout.size() {
            self.alloc_size.fetch_sub(layout.size() - new_size, Ordering::SeqCst);
        }
        System.realloc(ptr, layout, new_size)
    }
}

/// Mapping of C function / ISEQ name to integer indices
/// This is accessed at compilation time only (protected by a lock)
static mut CFUNC_NAME_TO_IDX: Option<HashMap<String, usize>> = None;
static mut ISEQ_NAME_TO_IDX: Option<HashMap<String, usize>> = None;

/// Vector of call counts for each C function / ISEQ index
/// This is modified (but not resized) by JITted code
static mut CFUNC_CALL_COUNT: Option<Vec<u64>> = None;
static mut ISEQ_CALL_COUNT: Option<Vec<u64>> = None;

/// Assign an index to a given cfunc name string
pub fn get_cfunc_idx(name: &str) -> usize {
    // SAFETY: We acquire a VM lock and don't create multiple &mut references to these static mut variables.
    unsafe { get_method_idx(name, &mut *addr_of_mut!(CFUNC_NAME_TO_IDX), &mut *addr_of_mut!(CFUNC_CALL_COUNT)) }
}

/// Assign an index to a given ISEQ name string
pub fn get_iseq_idx(name: &str) -> usize {
    // SAFETY: We acquire a VM lock and don't create multiple &mut references to these static mut variables.
    unsafe { get_method_idx(name, &mut *addr_of_mut!(ISEQ_NAME_TO_IDX), &mut *addr_of_mut!(ISEQ_CALL_COUNT)) }
}

fn get_method_idx(
    name: &str,
    method_name_to_idx: &mut Option<HashMap<String, usize>>,
    method_call_count: &mut Option<Vec<u64>>,
) -> usize {
    //println!("{}", name);

    let name_to_idx = method_name_to_idx.get_or_insert_with(HashMap::default);
    let call_count = method_call_count.get_or_insert_with(Vec::default);

    match name_to_idx.get(name) {
        Some(idx) => *idx,
        None => {
            let idx = name_to_idx.len();
            name_to_idx.insert(name.to_string(), idx);

            // Resize the call count vector
            if idx >= call_count.len() {
                call_count.resize(idx + 1, 0);
            }

            idx
        }
    }
}

// Increment the counter for a C function
pub extern "C" fn incr_cfunc_counter(idx: usize) {
    let cfunc_call_count = unsafe { CFUNC_CALL_COUNT.as_mut().unwrap() };
    assert!(idx < cfunc_call_count.len());
    cfunc_call_count[idx] += 1;
}

// Increment the counter for an ISEQ
pub extern "C" fn incr_iseq_counter(idx: usize) {
    let iseq_call_count = unsafe { ISEQ_CALL_COUNT.as_mut().unwrap() };
    assert!(idx < iseq_call_count.len());
    iseq_call_count[idx] += 1;
}

// YJIT exit counts for each instruction type
const VM_INSTRUCTION_SIZE_USIZE: usize = VM_INSTRUCTION_SIZE as usize;
static mut EXIT_OP_COUNT: [u64; VM_INSTRUCTION_SIZE_USIZE] = [0; VM_INSTRUCTION_SIZE_USIZE];

/// Global state needed for collecting backtraces of exits
pub struct YjitExitLocations {
    /// Vec to hold raw_samples which represent the control frames
    /// of method entries.
    raw_samples: Vec<VALUE>,
    /// Vec to hold line_samples which represent line numbers of
    /// the iseq caller.
    line_samples: Vec<i32>,
    /// Number of samples skipped when sampling
    skipped_samples: usize
}

/// Private singleton instance of yjit exit locations
static mut YJIT_EXIT_LOCATIONS: Option<YjitExitLocations> = None;

impl YjitExitLocations {
    /// Initialize the yjit exit locations
    pub fn init() {
        // Return if --yjit-trace-exits isn't enabled
        if get_option!(trace_exits).is_none() {
            return;
        }

        let yjit_exit_locations = YjitExitLocations {
            raw_samples: Vec::new(),
            line_samples: Vec::new(),
            skipped_samples: 0
        };

        // Initialize the yjit exit locations instance
        unsafe {
            YJIT_EXIT_LOCATIONS = Some(yjit_exit_locations);
        }
    }

    /// Get a mutable reference to the yjit exit locations globals instance
    pub fn get_instance() -> &'static mut YjitExitLocations {
        unsafe { YJIT_EXIT_LOCATIONS.as_mut().unwrap() }
    }

    /// Get a mutable reference to the yjit raw samples Vec
    pub fn get_raw_samples() -> &'static mut Vec<VALUE> {
        &mut YjitExitLocations::get_instance().raw_samples
    }

    /// Get a mutable reference to yjit the line samples Vec.
    pub fn get_line_samples() -> &'static mut Vec<i32> {
        &mut YjitExitLocations::get_instance().line_samples
    }

    /// Get the number of samples skipped
    pub fn get_skipped_samples() -> &'static mut usize {
        &mut YjitExitLocations::get_instance().skipped_samples
    }

    /// Mark the data stored in YjitExitLocations::get_raw_samples that needs to be used by
    /// rb_yjit_add_frame. YjitExitLocations::get_raw_samples are an array of
    /// VALUE pointers, exit instruction, and number of times we've seen this stack row
    /// as collected by rb_yjit_record_exit_stack.
    ///
    /// These need to have rb_gc_mark called so they can be used by rb_yjit_add_frame.
    pub fn gc_mark_raw_samples() {
        // Return if YJIT is not enabled
        if !yjit_enabled_p() {
            return;
        }

        // Return if --yjit-trace-exits isn't enabled
        if get_option!(trace_exits).is_none() {
            return;
        }

        let mut idx: size_t = 0;
        let yjit_raw_samples = YjitExitLocations::get_raw_samples();

        while idx < yjit_raw_samples.len() as size_t {
            let num = yjit_raw_samples[idx as usize];
            let mut i = 0;
            idx += 1;

            // Mark the yjit_raw_samples at the given index. These represent
            // the data that needs to be GC'd which are the current frames.
            while i < i32::from(num) {
                unsafe { rb_gc_mark(yjit_raw_samples[idx as usize]); }
                i += 1;
                idx += 1;
            }

            // Increase index for exit instruction.
            idx += 1;
            // Increase index for bookkeeping value (number of times we've seen this
            // row in a stack).
            idx += 1;
        }
    }
}

// Macro to declare the stat counters
macro_rules! make_counters {
    ($($counter_name:ident,)+) => {
        /// Struct containing the counter values
        #[derive(Default, Debug)]
        pub struct Counters { $(pub $counter_name: u64),+ }

        /// Enum to represent a counter
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, PartialEq, Eq, Debug)]
        pub enum Counter { $($counter_name),+ }

        impl Counter {
            /// Map a counter name string to a counter enum
            pub fn get(name: &str) -> Option<Counter> {
                match name {
                    $( stringify!($counter_name) => { Some(Counter::$counter_name) } ),+
                    _ => None,
                }
            }

            /// Get a counter name string
            pub fn get_name(&self) -> String {
                match self {
                    $( Counter::$counter_name => stringify!($counter_name).to_string() ),+
                }
            }
        }

        /// Global counters instance, initialized to zero
        pub static mut COUNTERS: Counters = Counters { $($counter_name: 0),+ };

        /// Counter names constant
        const COUNTER_NAMES: &'static [&'static str] = &[ $(stringify!($counter_name)),+ ];

        /// Map a counter name string to a counter pointer
        pub fn get_counter_ptr(name: &str) -> *mut u64 {
            match name {
                $( stringify!($counter_name) => { ptr_to_counter!($counter_name) } ),+
                _ => panic!()
            }
        }
    }
}

/// The list of counters that are available without --yjit-stats.
/// They are incremented only by `incr_counter!` and don't use `gen_counter_incr`.
pub const DEFAULT_COUNTERS: &'static [Counter] = &[
    Counter::code_gc_count,
    Counter::compiled_iseq_entry,
    Counter::cold_iseq_entry,
    Counter::compiled_iseq_count,
    Counter::compiled_blockid_count,
    Counter::compiled_block_count,
    Counter::deleted_defer_block_count,
    Counter::compiled_branch_count,
    Counter::compile_time_ns,
    Counter::max_inline_versions,
    Counter::num_contexts_encoded,
    Counter::context_cache_hits,

    Counter::invalidation_count,
    Counter::invalidate_method_lookup,
    Counter::invalidate_bop_redefined,
    Counter::invalidate_ractor_spawn,
    Counter::invalidate_constant_state_bump,
    Counter::invalidate_constant_ic_fill,
    Counter::invalidate_no_singleton_class,
    Counter::invalidate_ep_escape,
];

/// Macro to increase a counter by name and count
macro_rules! incr_counter_by {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($counter_name:ident, $count:expr) => {
        #[allow(unused_unsafe)]
        {
            unsafe { $crate::stats::COUNTERS.$counter_name += $count as u64 }
        }
    };
}
pub(crate) use incr_counter_by;

/// Macro to increase a counter if the given value is larger
macro_rules! incr_counter_to {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($counter_name:ident, $count:expr) => {
        #[allow(unused_unsafe)]
        {
            unsafe {
                $crate::stats::COUNTERS.$counter_name = u64::max(
                    $crate::stats::COUNTERS.$counter_name,
                    $count as u64,
                )
            }
        }
    };
}
pub(crate) use incr_counter_to;

/// Macro to increment a counter by name
macro_rules! incr_counter {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($counter_name:ident) => {
        #[allow(unused_unsafe)]
        {
            unsafe { $crate::stats::COUNTERS.$counter_name += 1 }
        }
    };
}
pub(crate) use incr_counter;

/// Macro to get a raw pointer to a given counter
macro_rules! ptr_to_counter {
    ($counter_name:ident) => {
        unsafe {
            let ctr_ptr = std::ptr::addr_of_mut!(COUNTERS.$counter_name);
            ctr_ptr
        }
    };
}
pub(crate) use ptr_to_counter;

// Declare all the counters we track
make_counters! {
    yjit_insns_count,

    // Method calls that fallback to dynamic dispatch
    send_singleton_class,
    send_ivar_set_method,
    send_zsuper_method,
    send_undef_method,
    send_optimized_method_block_call,
    send_call_block,
    send_call_kwarg,
    send_call_multi_ractor,
    send_cme_not_found,
    send_megamorphic,
    send_missing_method,
    send_refined_method,
    send_private_not_fcall,
    send_cfunc_kw_splat_non_nil,
    send_cfunc_splat_neg2,
    send_cfunc_argc_mismatch,
    send_cfunc_block_arg,
    send_cfunc_toomany_args,
    send_cfunc_tracing,
    send_cfunc_splat_with_kw,
    send_cfunc_splat_varg_ruby2_keywords,
    send_attrset_kwargs,
    send_attrset_block_arg,
    send_iseq_tailcall,
    send_iseq_arity_error,
    send_iseq_block_arg_type,
    send_iseq_clobbering_block_arg,
    send_iseq_complex_discard_extras,
    send_iseq_leaf_builtin_block_arg_block_param,
    send_iseq_kw_splat_non_nil,
    send_iseq_kwargs_mismatch,
    send_iseq_has_post,
    send_iseq_has_no_kw,
    send_iseq_accepts_no_kwarg,
    send_iseq_materialized_block,
    send_iseq_splat_not_array,
    send_iseq_splat_with_kw,
    send_iseq_missing_optional_kw,
    send_iseq_too_many_kwargs,
    send_not_implemented_method,
    send_getter_arity,
    send_getter_block_arg,
    send_args_splat_attrset,
    send_args_splat_bmethod,
    send_args_splat_aref,
    send_args_splat_aset,
    send_args_splat_opt_call,
    send_iseq_splat_arity_error,
    send_splat_too_long,
    send_send_wrong_args,
    send_send_null_mid,
    send_send_null_cme,
    send_send_nested,
    send_send_attr_reader,
    send_send_attr_writer,
    send_iseq_has_rest_and_captured,
    send_iseq_has_kwrest_and_captured,
    send_iseq_has_rest_and_kw_supplied,
    send_iseq_has_rest_opt_and_block,
    send_bmethod_ractor,
    send_bmethod_block_arg,
    send_optimized_block_arg,

    invokesuper_defined_class_mismatch,
    invokesuper_kw_splat,
    invokesuper_kwarg,
    invokesuper_megamorphic,
    invokesuper_no_cme,
    invokesuper_no_me,
    invokesuper_not_iseq_or_cfunc,
    invokesuper_refinement,
    invokesuper_singleton_class,

    invokeblock_megamorphic,
    invokeblock_none,
    invokeblock_iseq_arg0_optional,
    invokeblock_iseq_arg0_args_splat,
    invokeblock_iseq_arg0_not_array,
    invokeblock_iseq_arg0_wrong_len,
    invokeblock_iseq_not_inlined,
    invokeblock_ifunc_args_splat,
    invokeblock_ifunc_kw_splat,
    invokeblock_proc,
    invokeblock_symbol,

    // Method calls that exit to the interpreter
    guard_send_block_arg_type,
    guard_send_getter_splat_non_empty,
    guard_send_klass_megamorphic,
    guard_send_se_cf_overflow,
    guard_send_se_protected_check_failed,
    guard_send_splatarray_length_not_equal,
    guard_send_splatarray_last_ruby2_keywords,
    guard_send_splat_not_array,
    guard_send_send_name_chain,
    guard_send_iseq_has_rest_and_splat_too_few,
    guard_send_is_a_class_mismatch,
    guard_send_instance_of_class_mismatch,
    guard_send_interrupted,
    guard_send_not_fixnums,
    guard_send_not_fixnum_or_flonum,
    guard_send_not_string,
    guard_send_respond_to_mid_mismatch,

    guard_send_cfunc_bad_splat_vargs,

    guard_invokesuper_me_changed,

    guard_invokeblock_tag_changed,
    guard_invokeblock_iseq_block_changed,

    traced_cfunc_return,

    leave_se_interrupt,
    leave_interp_return,

    getivar_megamorphic,
    getivar_not_heap,

    setivar_not_heap,
    setivar_frozen,
    setivar_megamorphic,

    definedivar_not_heap,
    definedivar_megamorphic,

    setlocal_wb_required,

    invokebuiltin_too_many_args,

    opt_plus_overflow,
    opt_minus_overflow,
    opt_mult_overflow,

    opt_succ_not_fixnum,
    opt_succ_overflow,

    opt_mod_zero,
    opt_div_zero,

    lshift_amount_changed,
    lshift_overflow,

    rshift_amount_changed,

    opt_aref_argc_not_one,
    opt_aref_arg_not_fixnum,
    opt_aref_not_array,
    opt_aref_not_hash,

    opt_aset_not_array,
    opt_aset_not_fixnum,
    opt_aset_not_hash,

    opt_aref_with_qundef,

    opt_case_dispatch_megamorphic,

    opt_getconstant_path_ic_miss,
    opt_getconstant_path_multi_ractor,

    expandarray_splat,
    expandarray_postarg,
    expandarray_not_array,
    expandarray_to_ary,
    expandarray_chain_max_depth,

    // getblockparam
    gbp_wb_required,

    // getblockparamproxy
    gbpp_unsupported_type,
    gbpp_block_param_modified,
    gbpp_block_handler_not_none,
    gbpp_block_handler_not_iseq,
    gbpp_block_handler_not_proc,

    branchif_interrupted,
    branchunless_interrupted,
    branchnil_interrupted,
    jump_interrupted,

    objtostring_not_string,

    getbyte_idx_not_fixnum,
    getbyte_idx_negative,
    getbyte_idx_out_of_bounds,

    splatkw_not_hash,
    splatkw_not_nil,

    binding_allocations,
    binding_set,

    compiled_iseq_entry,
    cold_iseq_entry,
    compiled_iseq_count,
    compiled_blockid_count,
    compiled_block_count,
    compiled_branch_count,
    compile_time_ns,
    compilation_failure,
    block_next_count,
    defer_count,
    defer_empty_count,
    deleted_defer_block_count,
    branch_insn_count,
    branch_known_count,
    max_inline_versions,
    num_contexts_encoded,

    freed_iseq_count,

    exit_from_branch_stub,

    invalidation_count,
    invalidate_method_lookup,
    invalidate_bop_redefined,
    invalidate_ractor_spawn,
    invalidate_constant_state_bump,
    invalidate_constant_ic_fill,
    invalidate_no_singleton_class,
    invalidate_ep_escape,

    // Currently, it's out of the ordinary (might be impossible) for YJIT to leave gaps in
    // executable memory, so this should be 0.
    exec_mem_non_bump_alloc,

    code_gc_count,

    num_gc_obj_refs,

    num_send,
    num_send_known_class,
    num_send_polymorphic,
    num_send_x86_rel32,
    num_send_x86_reg,
    num_send_dynamic,
    num_send_cfunc,
    num_send_cfunc_inline,
    num_send_iseq,
    num_send_iseq_leaf,
    num_send_iseq_inline,

    num_getivar_megamorphic,
    num_setivar_megamorphic,
    num_opt_case_dispatch_megamorphic,

    num_throw,
    num_throw_break,
    num_throw_retry,
    num_throw_return,

    num_lazy_frame_check,
    num_lazy_frame_push,
    lazy_frame_count,
    lazy_frame_failure,

    iseq_stack_too_large,
    iseq_too_long,

    temp_reg_opnd,
    temp_mem_opnd,
    temp_spill,

    context_cache_hits,
}

//===========================================================================

/// Primitive called in yjit.rb
/// Check if stats generation is enabled
#[no_mangle]
pub extern "C" fn rb_yjit_stats_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {

    if get_option!(gen_stats) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb
/// Check if stats generation should print at exit
#[no_mangle]
pub extern "C" fn rb_yjit_print_stats_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if yjit_enabled_p() && get_option!(print_stats) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb.
/// Export all YJIT statistics as a Ruby hash.
#[no_mangle]
pub extern "C" fn rb_yjit_get_stats(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    with_vm_lock(src_loc!(), || rb_yjit_gen_stats_dict())
}

/// Primitive called in yjit.rb
///
/// Check if trace_exits generation is enabled. Requires the stats feature
/// to be enabled.
#[no_mangle]
pub extern "C" fn rb_yjit_trace_exit_locations_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if get_option!(trace_exits).is_some() {
        return Qtrue;
    }

    return Qfalse;
}

/// Call the C function to parse the raw_samples and line_samples
/// into raw, lines, and frames hash for RubyVM::YJIT.exit_locations.
#[no_mangle]
pub extern "C" fn rb_yjit_get_exit_locations(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    // Return if YJIT is not enabled
    if !yjit_enabled_p() {
        return Qnil;
    }

    // Return if --yjit-trace-exits isn't enabled
    if get_option!(trace_exits).is_none() {
        return Qnil;
    }

    // If the stats feature is enabled, pass yjit_raw_samples and yjit_line_samples
    // to the C function called rb_yjit_exit_locations_dict for parsing.
    let yjit_raw_samples = YjitExitLocations::get_raw_samples();
    let yjit_line_samples = YjitExitLocations::get_line_samples();

    // Assert that the two Vec's are the same length. If they aren't
    // equal something went wrong.
    assert_eq!(yjit_raw_samples.len(), yjit_line_samples.len());

    // yjit_raw_samples and yjit_line_samples are the same length so
    // pass only one of the lengths in the C function.
    let samples_len = yjit_raw_samples.len() as i32;

    unsafe {
        rb_yjit_exit_locations_dict(yjit_raw_samples.as_mut_ptr(), yjit_line_samples.as_mut_ptr(), samples_len)
    }
}

/// Increment a counter by name from the CRuby side
/// Warning: this is not fast because it requires a hash lookup, so don't use in tight loops
#[no_mangle]
pub extern "C" fn rb_yjit_incr_counter(counter_name: *const std::os::raw::c_char) {
    use std::ffi::CStr;
    let counter_name = unsafe { CStr::from_ptr(counter_name).to_str().unwrap() };
    let counter_ptr = get_counter_ptr(counter_name);
    unsafe { *counter_ptr += 1 };
}

/// Export all YJIT statistics as a Ruby hash.
fn rb_yjit_gen_stats_dict() -> VALUE {
    // If YJIT is not enabled, return Qnil
    if !yjit_enabled_p() {
        return Qnil;
    }

    macro_rules! hash_aset_usize {
        ($hash:ident, $counter_name:expr, $value:expr) => {
            let key = rust_str_to_sym($counter_name);
            let value = VALUE::fixnum_from_usize($value);
            rb_hash_aset($hash, key, value);
        }
    }

    let hash = unsafe { rb_hash_new() };

    unsafe {
        // Get the inline and outlined code blocks
        let cb = CodegenGlobals::get_inline_cb();
        let ocb = CodegenGlobals::get_outlined_cb();

        // Inline code size
        hash_aset_usize!(hash, "inline_code_size", cb.code_size());

        // Outlined code size
        hash_aset_usize!(hash, "outlined_code_size", ocb.unwrap().code_size());

        // GCed pages
        let freed_page_count = cb.num_freed_pages();
        hash_aset_usize!(hash, "freed_page_count", freed_page_count);

        // GCed code size
        hash_aset_usize!(hash, "freed_code_size", freed_page_count * cb.page_size());

        // Live pages
        hash_aset_usize!(hash, "live_page_count", cb.num_mapped_pages() - freed_page_count);

        // Size of memory region allocated for JIT code
        hash_aset_usize!(hash, "code_region_size", cb.mapped_region_size());

        // Rust global allocations in bytes
        hash_aset_usize!(hash, "yjit_alloc_size", GLOBAL_ALLOCATOR.alloc_size.load(Ordering::SeqCst));

        // How many bytes we are using to store context data
        let context_data = CodegenGlobals::get_context_data();
        hash_aset_usize!(hash, "context_data_bytes", context_data.num_bytes());
        hash_aset_usize!(hash, "context_cache_bytes", crate::core::CTX_CACHE_BYTES);

        // VM instructions count
        hash_aset_usize!(hash, "vm_insns_count", rb_vm_insns_count as usize);

        hash_aset_usize!(hash, "live_iseq_count", rb_yjit_live_iseq_count as usize);
        hash_aset_usize!(hash, "iseq_alloc_count", rb_yjit_iseq_alloc_count as usize);
    }

    // If we're not generating stats, put only default counters
    if !get_option!(gen_stats) {
        for counter in DEFAULT_COUNTERS {
            // Get the counter value
            let counter_ptr = get_counter_ptr(&counter.get_name());
            let counter_val = unsafe { *counter_ptr };

            // Put counter into hash
            let key = rust_str_to_sym(&counter.get_name());
            let value = VALUE::fixnum_from_usize(counter_val as usize);
            unsafe { rb_hash_aset(hash, key, value); }
        }

        return hash;
    }

    unsafe {
        // Indicate that the complete set of stats is available
        rb_hash_aset(hash, rust_str_to_sym("all_stats"), Qtrue);

        // For each counter we track
        for counter_name in COUNTER_NAMES {
            // Get the counter value
            let counter_ptr = get_counter_ptr(counter_name);
            let counter_val = *counter_ptr;

            // Put counter into hash
            let key = rust_str_to_sym(counter_name);
            let value = VALUE::fixnum_from_usize(counter_val as usize);
            rb_hash_aset(hash, key, value);
        }

        // For each entry in exit_op_count, add a stats entry with key "exit_INSTRUCTION_NAME"
        // and the value is the count of side exits for that instruction.
        for op_idx in 0..VM_INSTRUCTION_SIZE_USIZE {
            let op_name = insn_name(op_idx);
            let key_string = "exit_".to_owned() + &op_name;
            let key = rust_str_to_sym(&key_string);
            let value = VALUE::fixnum_from_usize(EXIT_OP_COUNT[op_idx] as usize);
            rb_hash_aset(hash, key, value);
        }

        // Set method call counts in a Ruby dict
        fn set_call_counts(
            calls_hash: VALUE,
            method_name_to_idx: &mut Option<HashMap<String, usize>>,
            method_call_count: &mut Option<Vec<u64>>,
        ) {
            if let (Some(name_to_idx), Some(call_counts)) = (method_name_to_idx, method_call_count) {
                // Create a list of (name, call_count) pairs
                let mut pairs = Vec::new();
                for (name, idx) in name_to_idx {
                    let count = call_counts[*idx];
                    pairs.push((name, count));
                }

                // Sort the vectors by decreasing call counts
                pairs.sort_by_key(|e| -(e.1 as i64));

                // Cap the number of counts reported to avoid
                // bloating log files, etc.
                pairs.truncate(20);

                // Add the pairs to the dict
                for (name, call_count) in pairs {
                    let key = rust_str_to_sym(name);
                    let value = VALUE::fixnum_from_usize(call_count as usize);
                    unsafe { rb_hash_aset(calls_hash, key, value); }
                }
            }
        }

        // Create a hash for the cfunc call counts
        let cfunc_calls = rb_hash_new();
        rb_hash_aset(hash, rust_str_to_sym("cfunc_calls"), cfunc_calls);
        set_call_counts(cfunc_calls, &mut *addr_of_mut!(CFUNC_NAME_TO_IDX), &mut *addr_of_mut!(CFUNC_CALL_COUNT));

        // Create a hash for the ISEQ call counts
        let iseq_calls = rb_hash_new();
        rb_hash_aset(hash, rust_str_to_sym("iseq_calls"), iseq_calls);
        set_call_counts(iseq_calls, &mut *addr_of_mut!(ISEQ_NAME_TO_IDX), &mut *addr_of_mut!(ISEQ_CALL_COUNT));
    }

    hash
}

/// Record the backtrace when a YJIT exit occurs. This functionality requires
/// that the stats feature is enabled as well as the --yjit-trace-exits option.
///
/// This function will fill two Vec's in YjitExitLocations to record the raw samples
/// and line samples. Their length should be the same, however the data stored in
/// them is different.
#[no_mangle]
pub extern "C" fn rb_yjit_record_exit_stack(_exit_pc: *const VALUE)
{
    // Return if YJIT is not enabled
    if !yjit_enabled_p() {
        return;
    }

    // Return if --yjit-trace-exits isn't enabled
    if get_option!(trace_exits).is_none() {
        return;
    }

    if get_option!(trace_exits_sample_rate) > 0 {
        if get_option!(trace_exits_sample_rate) <= *YjitExitLocations::get_skipped_samples() {
            YjitExitLocations::get_instance().skipped_samples = 0;
        } else {
            YjitExitLocations::get_instance().skipped_samples += 1;
            return;
        }
    }

    // rb_vm_insn_addr2opcode won't work in cargo test --all-features
    // because it's a C function. Without insn call, this function is useless
    // so wrap the whole thing in a not test check.
    #[cfg(not(test))]
    {
        // Get the opcode from the encoded insn handler at this PC
        let insn = unsafe { rb_vm_insn_addr2opcode((*_exit_pc).as_ptr()) };

        // Use the same buffer size as Stackprof.
        const BUFF_LEN: usize = 2048;

        // Create 2 array buffers to be used to collect frames and lines.
        let mut frames_buffer = [VALUE(0_usize); BUFF_LEN];
        let mut lines_buffer = [0; BUFF_LEN];

        // Records call frame and line information for each method entry into two
        // temporary buffers. Returns the number of times we added to the buffer (ie
        // the length of the stack).
        //
        // Call frame info is stored in the frames_buffer, line number information
        // in the lines_buffer. The first argument is the start point and the second
        // argument is the buffer limit, set at 2048.
        let stack_length = unsafe { rb_profile_frames(0, BUFF_LEN as i32, frames_buffer.as_mut_ptr(), lines_buffer.as_mut_ptr()) };
        let samples_length = (stack_length as usize) + 3;

        let yjit_raw_samples = YjitExitLocations::get_raw_samples();
        let yjit_line_samples = YjitExitLocations::get_line_samples();

        // If yjit_raw_samples is less than or equal to the current length of the samples
        // we might have seen this stack trace previously.
        if yjit_raw_samples.len() >= samples_length {
            let prev_stack_len_index = yjit_raw_samples.len() - samples_length;
            let prev_stack_len = i64::from(yjit_raw_samples[prev_stack_len_index]);
            let mut idx = stack_length - 1;
            let mut prev_frame_idx = 0;
            let mut seen_already = true;

            // If the previous stack length and current stack length are equal,
            // loop and compare the current frame to the previous frame. If they are
            // not equal, set seen_already to false and break out of the loop.
            if prev_stack_len == stack_length as i64 {
                while idx >= 0 {
                    let current_frame = frames_buffer[idx as usize];
                    let prev_frame = yjit_raw_samples[prev_stack_len_index + prev_frame_idx + 1];

                    // If the current frame and previous frame are not equal, set
                    // seen_already to false and break out of the loop.
                    if current_frame != prev_frame {
                        seen_already = false;
                        break;
                    }

                    idx -= 1;
                    prev_frame_idx += 1;
                }

                // If we know we've seen this stack before, increment the counter by 1.
                if seen_already {
                    let prev_idx = yjit_raw_samples.len() - 1;
                    let prev_count = i64::from(yjit_raw_samples[prev_idx]);
                    let new_count = prev_count + 1;

                    yjit_raw_samples[prev_idx] = VALUE(new_count as usize);
                    yjit_line_samples[prev_idx] = new_count as i32;

                    return;
                }
            }
        }

        yjit_raw_samples.push(VALUE(stack_length as usize));
        yjit_line_samples.push(stack_length);

        let mut idx = stack_length - 1;

        while idx >= 0 {
            let frame = frames_buffer[idx as usize];
            let line = lines_buffer[idx as usize];

            yjit_raw_samples.push(frame);
            yjit_line_samples.push(line);

            idx -= 1;
        }

        // Push the insn value into the yjit_raw_samples Vec.
        yjit_raw_samples.push(VALUE(insn as usize));

        // We don't know the line
        yjit_line_samples.push(0);

        // Push number of times seen onto the stack, which is 1
        // because it's the first time we've seen it.
        yjit_raw_samples.push(VALUE(1_usize));
        yjit_line_samples.push(1);
    }
}

/// Primitive called in yjit.rb. Zero out all the counters.
#[no_mangle]
pub extern "C" fn rb_yjit_reset_stats_bang(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    unsafe {
        EXIT_OP_COUNT = [0; VM_INSTRUCTION_SIZE_USIZE];
        COUNTERS = Counters::default();
    }

    return Qnil;
}

#[no_mangle]
pub extern "C" fn rb_yjit_collect_binding_alloc() {
    incr_counter!(binding_allocations);
}

#[no_mangle]
pub extern "C" fn rb_yjit_collect_binding_set() {
    incr_counter!(binding_set);
}

#[no_mangle]
pub extern "C" fn rb_yjit_count_side_exit_op(exit_pc: *const VALUE) -> *const VALUE {
    #[cfg(not(test))]
    unsafe {
        // Get the opcode from the encoded insn handler at this PC
        let opcode = rb_vm_insn_addr2opcode((*exit_pc).as_ptr());

        // Increment the exit op count for this opcode
        EXIT_OP_COUNT[opcode as usize] += 1;
    };

    // This function must return exit_pc!
    return exit_pc;
}

/// Measure the time taken by func() and add that to yjit_compile_time.
pub fn with_compile_time<F, R>(func: F) -> R where F: FnOnce() -> R {
    let start = Instant::now();
    let ret = func();
    let nanos = Instant::now().duration_since(start).as_nanos();
    incr_counter_by!(compile_time_ns, nanos);
    ret
}
