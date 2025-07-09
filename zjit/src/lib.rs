#![allow(dead_code)]
#![allow(static_mut_refs)]

// Add std docs to cargo doc.
#[doc(inline)]
pub use std;

mod state;
mod cruby;
mod cruby_methods;
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
#[cfg(test)]
mod assertions;
mod bitset;
mod gc;
