// Clippy disagreements
#![allow(clippy::style)] // We are laid back about style
#![allow(clippy::too_many_arguments)] // :shrug:
#![allow(clippy::identity_op)] // Sometimes we do it for style

// Temporary while switching to the new backend
#![allow(dead_code)]
#![allow(unused)]

mod asm;
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
