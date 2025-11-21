#![allow(dead_code)]
#![allow(static_mut_refs)]

#![allow(clippy::enum_variant_names)]
#![allow(clippy::too_many_arguments)]
#![allow(clippy::needless_bool)]

// Add std docs to cargo doc.
#[doc(inline)]
pub use std;

mod state;
mod distribution;
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
mod bitset;
mod gc;
mod payload;
mod json;
