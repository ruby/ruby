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
