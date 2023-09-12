use crate::codegen::*;
use crate::core::*;
use crate::cruby::*;
use crate::invariants::*;
use crate::options::*;
use crate::stats::YjitExitLocations;
use crate::stats::incr_counter;
use crate::stats::with_compile_time;

use std::os::raw;
use std::sync::atomic::{AtomicBool, Ordering};

/// For tracking whether the user enabled YJIT through command line arguments or environment
/// variables. AtomicBool to avoid `unsafe`. On x86 it compiles to simple movs.
/// See <https://doc.rust-lang.org/std/sync/atomic/enum.Ordering.html>
/// See [rb_yjit_enabled_p]
static YJIT_ENABLED: AtomicBool = AtomicBool::new(false);

/// When false, we don't compile new iseqs, but might still service existing branch stubs.
static COMPILE_NEW_ISEQS: AtomicBool = AtomicBool::new(false);

/// Parse one command-line option.
/// This is called from ruby.c
#[no_mangle]
pub extern "C" fn rb_yjit_parse_option(str_ptr: *const raw::c_char) -> bool {
    return parse_option(str_ptr).is_some();
}

/// Is YJIT on? The interpreter uses this function to decide whether to increment
/// ISEQ call counters. See jit_exec().
/// This is used frequently since it's used on every method call in the interpreter.
#[no_mangle]
pub extern "C" fn rb_yjit_enabled_p() -> raw::c_int {
    // Note that we might want to call this function from signal handlers so
    // might need to ensure signal-safety(7).
    YJIT_ENABLED.load(Ordering::Acquire).into()
}

#[no_mangle]
pub extern "C" fn rb_yjit_compile_new_iseqs() -> bool {
    COMPILE_NEW_ISEQS.load(Ordering::Acquire).into()
}

/// Like rb_yjit_enabled_p, but for Rust code.
pub fn yjit_enabled_p() -> bool {
    YJIT_ENABLED.load(Ordering::Acquire)
}

/// Test whether we are ready to compile an ISEQ or not
#[no_mangle]
pub extern "C" fn rb_yjit_threshold_hit(_iseq: IseqPtr, total_calls: u64) -> bool {
    let call_threshold = get_option!(call_threshold) as u64;
    return total_calls == call_threshold;
}

/// This function is called from C code
#[no_mangle]
pub extern "C" fn rb_yjit_init_rust() {
    // TODO: need to make sure that command-line options have been
    // initialized by CRuby

    // Catch panics to avoid UB for unwinding into C frames.
    // See https://doc.rust-lang.org/nomicon/exception-safety.html
    let result = std::panic::catch_unwind(|| {
        Invariants::init();
        CodegenGlobals::init();
        YjitExitLocations::init();

        rb_bug_panic_hook();

        // YJIT enabled and initialized successfully
        YJIT_ENABLED.store(true, Ordering::Release);

        COMPILE_NEW_ISEQS.store(!get_option!(pause), Ordering::Release);
    });

    if let Err(_) = result {
        println!("YJIT: rb_yjit_init_rust() panicked. Aborting.");
        std::process::abort();
    }
}

/// At the moment, we abort in all cases we panic.
/// To aid with getting diagnostics in the wild without requiring
/// people to set RUST_BACKTRACE=1, register a panic hook that crash using rb_bug().
/// rb_bug() might not be as good at printing a call trace as Rust's stdlib, but
/// it dumps some other info that might be relevant.
///
/// In case we want to start doing fancier exception handling with panic=unwind,
/// we can revisit this later. For now, this helps to get us good bug reports.
fn rb_bug_panic_hook() {
    use std::env;
    use std::panic;
    use std::io::{stderr, Write};

    // Probably the default hook. We do this very early during process boot.
    let previous_hook = panic::take_hook();

    panic::set_hook(Box::new(move |panic_info| {
        // Not using `eprintln` to avoid double panic.
        let _ = stderr().write_all(b"ruby: YJIT has panicked. More info to follow...\n");

        // Always show a Rust backtrace.
        env::set_var("RUST_BACKTRACE", "1");
        previous_hook(panic_info);

        unsafe { rb_bug(b"YJIT panicked\0".as_ref().as_ptr() as *const raw::c_char); }
    }));
}

/// Called from C code to begin compiling a function
/// NOTE: this should be wrapped in RB_VM_LOCK_ENTER(), rb_vm_barrier() on the C side
/// If jit_exception is true, compile JIT code for handling exceptions.
/// See [jit_compile_exception] for details.
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_gen_entry_point(iseq: IseqPtr, ec: EcPtr, jit_exception: bool) -> *const u8 {
    // Reject ISEQs with very large temp stacks,
    // this will allow us to use u8/i8 values to track stack_size and sp_offset
    let stack_max = unsafe { rb_get_iseq_body_stack_max(iseq) };
    if stack_max >= i8::MAX as u32 {
        incr_counter!(iseq_stack_too_large);
        return std::ptr::null();
    }

    // Reject ISEQs that are too long,
    // this will allow us to use u16 for instruction indices if we want to,
    // very long ISEQs are also much more likely to be initialization code
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    if iseq_size >= u16::MAX as u32 {
        incr_counter!(iseq_too_long);
        return std::ptr::null();
    }

    let maybe_code_ptr = with_compile_time(|| { gen_entry_point(iseq, ec, jit_exception) });

    match maybe_code_ptr {
        Some(ptr) => ptr.raw_ptr(),
        None => std::ptr::null(),
    }
}

/// Free and recompile all existing JIT code
#[no_mangle]
pub extern "C" fn rb_yjit_code_gc(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if !yjit_enabled_p() {
        return Qnil;
    }

    with_vm_lock(src_loc!(), || {
        let cb = CodegenGlobals::get_inline_cb();
        let ocb = CodegenGlobals::get_outlined_cb();
        cb.code_gc(ocb);
    });

    Qnil
}

#[no_mangle]
pub extern "C" fn rb_yjit_resume(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if yjit_enabled_p() {
        COMPILE_NEW_ISEQS.store(true, Ordering::Release);
    }

    Qnil
}

/// Simulate a situation where we are out of executable memory
#[no_mangle]
pub extern "C" fn rb_yjit_simulate_oom_bang(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    // If YJIT is not enabled, do nothing
    if !yjit_enabled_p() {
        return Qnil;
    }

    // Enabled in debug mode only for security
    if cfg!(debug_assertions) {
        let cb = CodegenGlobals::get_inline_cb();
        let ocb = CodegenGlobals::get_outlined_cb().unwrap();
        cb.set_pos(cb.get_mem_size());
        ocb.set_pos(ocb.get_mem_size());
    }

    return Qnil;
}
