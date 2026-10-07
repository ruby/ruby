//! Regular expression engine for CRuby, ported from Onigmo.
//!
//! The parser, compiler and matcher live here. The encoding layer
//! (`OnigEncodingType` and `enc/*.c`) stays in C and is reached through its
//! function table. `unsafe` is confined to the modules that talk to C.

#![deny(unsafe_code)]
// The port keeps the control flow of the C code so that the two can be read
// side by side, which these lints would rewrite.
#![allow(clippy::collapsible_match, clippy::needless_late_init)]

pub mod ast;
pub mod bytecode;
pub mod compile;
pub mod enc;
pub mod error;
pub mod exec;
mod ffi;
pub mod names;
pub mod parser;
pub mod syntax;
mod utf8;

pub use ffi::*;
