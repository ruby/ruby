// Clippy disagreements
#![allow(clippy::style)] // We are laid back about style
#![allow(clippy::too_many_arguments)] // :shrug:
#![allow(clippy::identity_op)] // Sometimes we do it for style

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
