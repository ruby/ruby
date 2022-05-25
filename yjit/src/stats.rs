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
            unsafe { COUNTERS.$counter_name += 1 }
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
