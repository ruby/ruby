//! Everything related to the collection of runtime stats in YJIT
//! See the stats feature and the --yjit-stats command-line option

#![allow(dead_code)] // Counters are only used with the stats features

use crate::codegen::CodegenGlobals;
use crate::cruby::*;
use crate::options::*;
use crate::yjit::yjit_enabled_p;

// YJIT exit counts for each instruction type
const VM_INSTRUCTION_SIZE_USIZE:usize = VM_INSTRUCTION_SIZE as usize;
static mut EXIT_OP_COUNT: [u64; VM_INSTRUCTION_SIZE_USIZE] = [0; VM_INSTRUCTION_SIZE_USIZE];

/// Global state needed for collecting backtraces of exits
pub struct YjitExitLocations {
    /// Vec to hold raw_samples which represent the control frames
    /// of method entries.
    raw_samples: Vec<VALUE>,
    /// Vec to hold line_samples which represent line numbers of
    /// the iseq caller.
    line_samples: Vec<i32>
}

/// Private singleton instance of yjit exit locations
static mut YJIT_EXIT_LOCATIONS: Option<YjitExitLocations> = None;

impl YjitExitLocations {
    /// Initialize the yjit exit locations
    pub fn init() {
        // Return if the stats feature is disabled
        if !cfg!(feature = "stats") {
            return;
        }

        // Return if --yjit-trace-exits isn't enabled
        if !get_option!(gen_trace_exits) {
            return;
        }

        let yjit_exit_locations = YjitExitLocations {
            raw_samples: Vec::new(),
            line_samples: Vec::new()
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

        // Return if the stats feature is disabled
        if !cfg!(feature = "stats") {
            return;
        }

        // Return if --yjit-trace-exits isn't enabled
        if !get_option!(gen_trace_exits) {
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
            // Increase index for bookeeping value (number of times we've seen this
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

        /// Global counters instance, initialized to zero
        pub static mut COUNTERS: Counters = Counters { $($counter_name: 0),+ };

        /// Counter names constant
        const COUNTER_NAMES: &'static [&'static str] = &[ $(stringify!($counter_name)),+ ];

        /// Map a counter name string to a counter pointer
        fn get_counter_ptr(name: &str) -> *mut u64 {
            match name {
                $( stringify!($counter_name) => { ptr_to_counter!($counter_name) } ),+
                _ => panic!()
            }
        }
    }
}

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

    // Currently, it's out of the ordinary (might be impossible) for YJIT to leave gaps in
    // executable memory, so this should be 0.
    exec_mem_non_bump_alloc,
}

//===========================================================================

/// Primitive called in yjit.rb
/// Check if stats generation is enabled
#[no_mangle]
pub extern "C" fn rb_yjit_stats_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    #[cfg(feature = "stats")]
    if get_option!(gen_stats) {
        return Qtrue;
    }

    return Qfalse;
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
    #[cfg(feature = "stats")]
    if get_option!(gen_trace_exits) {
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

    // Return if the stats feature is disabled
    if !cfg!(feature = "stats") {
        return Qnil;
    }

    // Return if --yjit-trace-exits isn't enabled
    if !get_option!(gen_trace_exits) {
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

/// Export all YJIT statistics as a Ruby hash.
fn rb_yjit_gen_stats_dict() -> VALUE {
    // If YJIT is not enabled, return Qnil
    if !yjit_enabled_p() {
        return Qnil;
    }

    let hash = unsafe { rb_hash_new() };

    // Inline and outlined code size
    unsafe {
        // Get the inline and outlined code blocks
        let cb = CodegenGlobals::get_inline_cb();
        let ocb = CodegenGlobals::get_outlined_cb();

        // Inline code size
        let key = rust_str_to_sym("inline_code_size");
        let value = VALUE::fixnum_from_usize(cb.get_write_pos());
        rb_hash_aset(hash, key, value);

        // Outlined code size
        let key = rust_str_to_sym("outlined_code_size");
        let value = VALUE::fixnum_from_usize(ocb.unwrap().get_write_pos());
        rb_hash_aset(hash, key, value);
    }

    // If we're not generating stats, the hash is done
    if !get_option!(gen_stats) {
        return hash;
    }

    // If the stats feature is enabled
    #[cfg(feature = "stats")]
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
pub extern "C" fn rb_yjit_record_exit_stack(exit_pc: *const VALUE)
{
    // Return if YJIT is not enabled
    if !yjit_enabled_p() {
        return;
    }

    // Return if the stats feature is disabled
    if !cfg!(feature = "stats") {
        return;
    }

    // Return if --yjit-trace-exits isn't enabled
    if !get_option!(gen_trace_exits) {
        return;
    }

    // rb_vm_insn_addr2opcode won't work in cargo test --all-features
    // because it's a C function. Without insn call, this function is useless
    // so wrap the whole thing in a not test check.
    if cfg!(not(test)) {
        // Get the opcode from the encoded insn handler at this PC
        let insn = unsafe { rb_vm_insn_addr2opcode((*exit_pc).as_ptr()) };

        // Use the same buffer size as Stackprof.
        const BUFF_LEN: usize = 2048;

        // Create 2 array buffers to be used to collect frames and lines.
        let mut frames_buffer = [VALUE(0 as usize); BUFF_LEN];
        let mut lines_buffer = [0; BUFF_LEN];

        // Records call frame and line information for each method entry into two
        // temporary buffers. Returns the number of times we added to the buffer (ie
        // the length of the stack).
        //
        // Call frame info is stored in the frames_buffer, line number information
        // in the lines_buffer. The first argument is the start point and the second
        // argument is the buffer limit, set at 2048.
        let num = unsafe { rb_profile_frames(0, BUFF_LEN as i32, frames_buffer.as_mut_ptr(), lines_buffer.as_mut_ptr()) };

        let mut i = num - 1;
        let yjit_raw_samples = YjitExitLocations::get_raw_samples();
        let yjit_line_samples = YjitExitLocations::get_line_samples();

        yjit_raw_samples.push(VALUE(num as usize));
        yjit_line_samples.push(num);

        while i >= 0 {
            let frame = frames_buffer[i as usize];
            let line = lines_buffer[i as usize];

            yjit_raw_samples.push(frame);
            yjit_line_samples.push(line);

            i -= 1;
        }

        // Push the insn value into the yjit_raw_samples Vec.
        yjit_raw_samples.push(VALUE(insn as usize));

        // Push the current line onto the yjit_line_samples Vec. This
        // points to the line in insns.def.
        let line = yjit_line_samples.len() - 1;
        yjit_line_samples.push(line as i32);

        yjit_raw_samples.push(VALUE(1 as usize));
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

/// Increment the number of instructions executed by the interpreter
#[no_mangle]
pub extern "C" fn rb_yjit_collect_vm_usage_insn() {
    incr_counter!(vm_insns_count);
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
