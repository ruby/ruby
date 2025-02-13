#![allow(dead_code)]
#![allow(static_mut_refs)]

mod state;
mod cruby;
mod ir;
mod codegen;
mod stats;
mod cast;
mod virtualmem;
mod asm;
mod backend;
mod disasm;
mod options;

use codegen::gen_function;
use options::{debug, get_option, Options};
use state::ZJITState;
use crate::cruby::*;

#[allow(non_upper_case_globals)]
#[no_mangle]
pub static mut rb_zjit_enabled_p: bool = false;

/// Initialize ZJIT, given options allocated by rb_zjit_init_options()
#[no_mangle]
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
    use std::env;
    use std::panic;
    use std::io::{stderr, Write};

    // Probably the default hook. We do this very early during process boot.
    let previous_hook = panic::take_hook();

    panic::set_hook(Box::new(move |panic_info| {
        // Not using `eprintln` to avoid double panic.
        let _ = stderr().write_all(b"ruby: ZJIT has panicked. More info to follow...\n");

        // Always show a Rust backtrace.
        env::set_var("RUST_BACKTRACE", "1");
        previous_hook(panic_info);

        // TODO: enable CRuby's SEGV handler
        // Abort with rb_bug(). It has a length limit on the message.
        //let panic_message = &format!("{}", panic_info)[..];
        //let len = std::cmp::min(0x100, panic_message.len()) as c_int;
        //unsafe { rb_bug(b"ZJIT: %*s\0".as_ref().as_ptr() as *const c_char, len, panic_message.as_ptr()); }
    }));
}

/// Generate JIT code for a given ISEQ, which takes EC and CFP as its arguments.
#[no_mangle]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    // TODO: acquire the VM barrier

    // Compile ISEQ into SSA IR
    let ssa = match ir::iseq_to_ssa(iseq) {
        Ok(ssa) => ssa,
        Err(err) => {
            debug!("ZJIT: to_ssa: {:?}", err);
            return std::ptr::null();
        }
    };

    // Compile SSA IR into machine code (TODO)
    let cb = ZJITState::get_code_block();
    match gen_function(cb, &ssa) {
        Some(start_ptr) => start_ptr.raw_ptr(cb),
        None => std::ptr::null(),
    }
}
