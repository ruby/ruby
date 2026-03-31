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
mod hir_effect;
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
mod jit_frame;
mod payload;
mod json;
mod ttycolors;

/// Pull in YJIT's symbols for linking the test binary in `make zjit-test`. The test binary builds
/// ZJIT symbols and they should take precendence over the ones built for miniruby, so libminiruby
/// doesn't include any ZJIT code. But, in removing from libminiruby the object which contains all
/// rust code, including ZJIT code, we also remove all YJIT symbols which the rest of libminiruby
/// might request in YJIT+ZJIT configurations. We add back the YJIT symbols here.
///
/// Only relevant for YJIT+ZJIT configurations, but building YJIT is fast, so always do it for the
/// test binary for simplicity.
#[cfg(test)]
use yjit as _;
