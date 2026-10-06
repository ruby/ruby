//! Functions exported to C. Every symbol is named `rb_regexp_rust_*` because
//! the partial link of the Rust static library keeps only `rb_*` globals.

#![allow(unsafe_code)]

/// Version of the interface between this crate and `regexp.c`. The C side
/// refuses to use the engine when its own copy of the number differs.
pub const ABI_VERSION: u32 = 1;

#[unsafe(no_mangle)]
pub extern "C" fn rb_regexp_rust_abi_version() -> u32 {
    ABI_VERSION
}
