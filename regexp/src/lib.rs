//! Regular expression engine for CRuby, ported from Onigmo.
//!
//! The parser, compiler and matcher live here. The encoding layer
//! (`OnigEncodingType` and `enc/*.c`) stays in C and is reached through its
//! function table. `unsafe` is confined to the modules that talk to C.

#![deny(unsafe_code)]

mod ffi;

pub use ffi::*;
