//! Bindings to CRuby's C API for ports that handle Ruby objects (Wave B).
//!
//! Wave A ports never touch Ruby objects and need nothing from here.  Wave B
//! ports take and return `VALUE`s and call public C API functions; they use
//! these bindings instead of declaring their own, so every port agrees on the
//! same, checked definitions.
//!
//! * [`value`]: `VALUE`, `ID`, the special constants and the inline helpers
//!   of `include/ruby/internal/special_consts.h` and
//!   `include/ruby/internal/arithmetic/{long,fixnum}.h`, transcribed from the
//!   C (same formulas, same wrapping arithmetic).
//! * [`api`]: `extern "C"` declarations of public C API functions and
//!   globals, with the exact prototypes of `include/ruby/`.  Add a function
//!   here (with its prototype copied from the header) when a port needs it.
//!   Never declare internal (`internal/*.h`) functions here; a port that
//!   needs one is out of Wave B.
//! * [`protect`]: [`protect::protect`] around `rb_protect()`,
//!   [`protect::protect_with_cleanup`] for executing cleanup closures before
//!   re-raising, [`protect::protect_call!`] macro, and [`protect::jump_tag`]
//!   to re-raise.
//!
//! # Exception safety (AGENTS.md §6.9)
//!
//! A Ruby exception (`rb_raise()`, and any C API function that can raise,
//! which is most of them) and `throw`/`break` leave C with `longjmp()`.
//! `longjmp()` does not unwind Rust frames: it discards them.  Discarding a
//! frame that still owns a value with a destructor (`Drop`) is undefined
//! behaviour in Rust, and it would also skip the cleanup.  Therefore:
//!
//! 1. **A Rust frame that calls a C function that can raise holds no live
//!    `Drop` value at the call**, and neither does any Rust frame between it
//!    and the C caller.  core_rs is `no_std` without allocation, so in
//!    practice this means no guards, no `RefCell` borrows and no types with
//!    `impl Drop` across such calls.
//! 2. **Otherwise, call the raising code through [`protect::protect`],
//!    [`protect::protect_with_cleanup`], or [`protect_call!`]**, finish the
//!    cleanup, then re-raise with [`protect::jump_tag`].  This is the C idiom
//!    `rb_protect()` + `rb_jump_tag()`.
//! 3. **A Rust panic is never a Ruby exception.**  core_rs is built with
//!    `-C panic=abort`, and the panic handler calls `rb_bug()`.  Report Ruby
//!    errors with `rb_raise()` exactly where the C does, with the same class
//!    and message.
//!
//! Like the C it replaces, code using these bindings must run on a Ruby
//! thread that holds the GVL, with the VM initialised.

pub mod api;
pub mod protect;
pub mod value;

pub use protect::{jump_tag, protect, protect_call, protect_with_cleanup};
pub use value::{ID, SIGNED_VALUE, VALUE};
