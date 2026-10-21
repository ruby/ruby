//! Ruby on Rust core: C functions of CRuby ported to Rust.
//!
//! Rules for everything in this crate (see AGENTS.md §6):
//!
//! * Each port is *faithful*: it behaves exactly like the C function it
//!   replaces, including edge cases and wrapping arithmetic.  The original C
//!   stays in place behind `#if !USE_RUST_PORTS`, so any build can be
//!   switched back with `./configure --without-rust-ports`.
//! * Parsing and other logic live in safe Rust functions over slices or
//!   iterators.  `unsafe` is confined to the `extern "C"` boundary, which
//!   turns C pointers into those safe inputs and writes results back.
//! * No external crates, no allocation, `no_std`.  The crate is compiled by
//!   rustc alone (see core_rs/core_rs.mk); cargo is never required.
//! * Exported symbols use the names of the C functions they replace and must
//!   start with `rb_` or `ruby_`; everything else is localized when the
//!   staticlib is partially linked into libruby.
//! * Ports that handle Ruby objects (Wave B) use the C API bindings in
//!   [`ffi`] and follow its exception-safety rule.

#![cfg_attr(not(test), no_std)]
#![deny(unsafe_op_in_unsafe_fn)]

extern crate alloc as std_alloc;

pub mod alloc;
pub mod complex;
pub mod ffi;
pub mod pack;
pub mod re;
pub mod util;

/// C runtime pieces that `no_std` code needs.
mod libc {
    use core::ffi::c_int;

    unsafe extern "C" {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        fn __errno_location() -> *mut c_int;
        #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
        fn __error() -> *mut c_int;
    }

    #[cfg(target_os = "linux")]
    pub const EINVAL: c_int = 22;
    #[cfg(target_os = "linux")]
    pub const ERANGE: c_int = 34;
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
    pub const EINVAL: c_int = 22;
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
    pub const ERANGE: c_int = 34;

    /// Equivalent of `errno = value;` in C.
    pub fn set_errno(value: c_int) {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        // SAFETY: __errno_location() returns this thread's errno slot.
        unsafe {
            *__errno_location() = value
        };
        #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
        // SAFETY: __error() returns this thread's errno slot.
        unsafe {
            *__error() = value
        };
    }
}

/// A Rust panic in core_rs is a bug.  Report it through rb_bug() so that it
/// produces Ruby's usual crash report (backtraces, `ruby -v` output) instead
/// of a silent abort.
#[cfg(not(test))]
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    use core::ffi::{c_char, c_int, c_uint};
    unsafe extern "C" {
        fn rb_bug(fmt: *const c_char, ...) -> !;
    }
    let (file, line) = match info.location() {
        Some(loc) => (loc.file(), loc.line()),
        None => ("<unknown>", 0),
    };
    // SAFETY: "%.*s" reads exactly file.len() bytes from file.as_ptr().
    unsafe {
        rb_bug(
            c"core_rs: Rust panic at %.*s:%u".as_ptr(),
            file.len() as c_int,
            file.as_ptr() as *const c_char,
            line as c_uint,
        )
    }
}
