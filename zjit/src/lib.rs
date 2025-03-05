#![allow(dead_code)]
#![allow(static_mut_refs)]

// Add std docs to cargo doc.
#[doc(inline)]
pub use std;

mod state;
mod cruby;
mod hir;
mod hir_type;
mod codegen;
mod stats;
mod cast;
mod virtualmem;
mod asm;
mod backend;
#[cfg(feature = "disasm")]
mod disasm;
mod options;
mod profile;
mod invariants;

use codegen::gen_function;
use options::{debug, get_option, Options};
use state::ZJITState;
use crate::cruby::*;

#[allow(non_upper_case_globals)]
#[unsafe(no_mangle)]
pub static mut rb_zjit_enabled_p: bool = false;

/// Like rb_zjit_enabled_p, but for Rust code.
pub fn zjit_enabled_p() -> bool {
    unsafe { rb_zjit_enabled_p }
}

/// Initialize ZJIT, given options allocated by rb_zjit_init_options()
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init(options: *const u8) {
    // Catch panics to avoid UB for unwinding into C frames.
    // See https://doc.rust-lang.org/nomicon/exception-safety.html
    let result = std::panic::catch_unwind(|| {
        let options = unsafe { Box::from_raw(options as *mut Options) };
        ZJITState::init(*options);
        std::mem::drop(options);

        rb_bug_panic_hook();

        // YJIT enabled and initialized successfully
        assert!(unsafe{ !rb_zjit_enabled_p });
        unsafe { rb_zjit_enabled_p = true; }
    });

    if let Err(_) = result {
        println!("ZJIT: zjit_init() panicked. Aborting.");
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
    use std::panic;
    use std::io::{stderr, Write};

    panic::set_hook(Box::new(move |panic_info| {
        // Not using `eprintln` to avoid double panic.
        _ = write!(stderr(),
"ruby: ZJIT has panicked. More info to follow...
{panic_info}
{}",
            std::backtrace::Backtrace::force_capture());

        // TODO: enable CRuby's SEGV handler
        // Abort with rb_bug(). It has a length limit on the message.
        //let panic_message = &format!("{}", panic_info)[..];
        //let len = std::cmp::min(0x100, panic_message.len()) as c_int;
        //unsafe { rb_bug(b"ZJIT: %*s\0".as_ref().as_ptr() as *const c_char, len, panic_message.as_ptr()); }
    }));
}

/// Generate JIT code for a given ISEQ, which takes EC and CFP as its arguments.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    // TODO: acquire the VM barrier

    // Compile ISEQ into High-level IR
    let ssa = match hir::iseq_to_hir(iseq) {
        Ok(ssa) => ssa,
        Err(err) => {
            debug!("ZJIT: iseq_to_hir: {:?}", err);
            return std::ptr::null();
        }
    };

    // Compile High-level IR into machine code
    let cb = ZJITState::get_code_block();
    match gen_function(cb, &ssa, iseq) {
        Some(start_ptr) => start_ptr.raw_ptr(cb),

        // Compilation failed, continue executing in the interpreter only
        None => std::ptr::null(),
    }
}
