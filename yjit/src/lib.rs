// Clippy disagreements
#![allow(clippy::style)] // We are laid back about style
#![allow(clippy::too_many_arguments)] // :shrug:
#![allow(clippy::identity_op)] // Sometimes we do it for style

// TODO(alan): This lint is right -- the way we use `static mut` is UB happy. We have many globals
// and take `&mut` frequently, sometimes with a method that easily allows calling it twice.
//
// All of our globals rely on us running single threaded, which outside of boot-time relies on the
// VM lock (which signals and waits for all other threads to pause). To fix this properly, we should
// gather up all the globals into a struct to centralize the safety reasoning. That way we can also
// check for re-entrance in one place.
//
// We're too close to release to do that, though, so disable the lint for now.
#![allow(unknown_lints)]
#![allow(static_mut_refs)]
#![warn(unknown_lints)]

// Release builds of only YJIT compile the shared code into this crate;
// Cargo and combo builds link it as a crate.
// Not named `jit`: a crate-root `jit` item makes rustc load the `jit` crate from Cargo's
// extern prelude, bringing in a second #[global_allocator].
#[cfg(feature = "stats_allocator")]
#[path = "../../jit/src/lib.rs"]
mod shared_jit;
#[cfg(not(feature = "stats_allocator"))]
use ::jit as shared_jit;

pub mod asm;
mod backend;
mod codegen;
mod core;
mod cruby;
mod disasm;
mod invariants;
mod options;
mod stats;
mod utils;
mod yjit;
mod virtualmem;
mod log;
