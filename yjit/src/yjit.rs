use crate::codegen::*;
use crate::core::*;
use crate::cruby::*;
use crate::invariants::*;
use crate::options::*;
use crate::stats::YjitExitLocations;

use std::os::raw;
use std::sync::atomic::{AtomicBool, Ordering};

/// For tracking whether the user enabled YJIT through command line arguments or environment
/// variables. AtomicBool to avoid `unsafe`. On x86 it compiles to simple movs.
/// See <https://doc.rust-lang.org/std/sync/atomic/enum.Ordering.html>
/// See [rb_yjit_enabled_p]
static YJIT_ENABLED: AtomicBool = AtomicBool::new(false);

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

/// Like rb_yjit_enabled_p, but for Rust code.
pub fn yjit_enabled_p() -> bool {
    YJIT_ENABLED.load(Ordering::Acquire)
}

/// After how many calls YJIT starts compiling a method
#[no_mangle]
pub extern "C" fn rb_yjit_call_threshold() -> raw::c_uint {
    get_option!(call_threshold) as raw::c_uint
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
/// In case we want to do start doing fancier exception handling with panic=unwind,
/// we can revisit this later. For now, this helps to get us good bug reports.
fn rb_bug_panic_hook() {
    use std::panic;
    use std::io::{stderr, Write};

    // Probably the default hook. We do this very early during process boot.
    let previous_hook = panic::take_hook();

    panic::set_hook(Box::new(move |panic_info| {
        // Not using `eprintln` to avoid double panic.
        let _ = stderr().write_all(b"ruby: YJIT has panicked. More info to follow...\n");

        previous_hook(panic_info);

        unsafe { rb_bug(b"YJIT panicked\0".as_ref().as_ptr() as *const raw::c_char); }
    }));
}

/// Called from C code to begin compiling a function
/// NOTE: this should be wrapped in RB_VM_LOCK_ENTER(), rb_vm_barrier() on the C side
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_gen_entry_point(iseq: IseqPtr, ec: EcPtr) -> *const u8 {
    let maybe_code_ptr = gen_entry_point(iseq, ec);

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

    let cb = CodegenGlobals::get_inline_cb();
    cb.code_gc();
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
