//! C API declarations of CRuby functions that can raise Ruby exceptions.
//!
//! # Exception Safety Warning
//! Functions in this module can raise Ruby exceptions (`rb_raise`, `NoMemoryError`,
//! `TypeError`, `RangeError`, `FrozenError`, etc.) which perform a C `longjmp`.
//! `longjmp` unwinds C stack frames but bypasses Rust stack frames without running
//! Rust destructors (`Drop`).
//!
//! Calling any function in this module directly requires that:
//! 1. No live values implementing `Drop` exist in the caller's frame or any
//!    intermediate Rust frame between it and the C boundary.
//! 2. Or, the call is made via [`crate::ffi::protect::protect()`].

#![allow(non_upper_case_globals)]

use crate::ffi::value::{ID, VALUE};
use core::ffi::{c_char, c_double, c_int, c_long, c_ulong};

/// Zero-sized marker token asserting that the caller has manually verified
/// exception safety before invoking a raising C API function outside of `protect()`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct UnprotectedTag(());

impl UnprotectedTag {
    /// Creates an `UnprotectedTag` proof token.
    ///
    /// # Safety
    /// The caller must guarantee that no live values with destructors (`Drop`)
    /// exist in the current frame or any intermediate Rust frame up to the C boundary.
    #[inline(always)]
    pub const unsafe fn unsafe_new() -> Self {
        Self(())
    }
}

unsafe extern "C" {
    // ---- exceptions: include/ruby/internal/error.h, intern/eval.h ----
    /// `void rb_raise(VALUE exc, const char *fmt, ...)`, noreturn.
    ///
    /// Raises a Ruby exception of class `exc`. Performs `longjmp`.
    #[doc(alias = "raising")]
    pub fn rb_raise(exc: VALUE, fmt: *const c_char, ...) -> !;

    // ---- numbers: include/ruby/internal/arithmetic/*.h, intern/bignum.h ----
    /// `long rb_num2long(VALUE num)`
    ///
    /// Converts `num` to `c_long`. Can raise `TypeError` or `RangeError`.
    #[doc(alias = "raising")]
    pub fn rb_num2long(num: VALUE) -> c_long;

    /// `unsigned long rb_num2ulong(VALUE num)`
    ///
    /// Converts `num` to `c_ulong`. Can raise `TypeError` or `RangeError`.
    #[doc(alias = "raising")]
    pub fn rb_num2ulong(num: VALUE) -> c_ulong;

    /// `double rb_num2dbl(VALUE num)`
    ///
    /// Converts `num` to `c_double`. Can raise `TypeError`.
    #[doc(alias = "raising")]
    pub fn rb_num2dbl(num: VALUE) -> c_double;

    /// `VALUE rb_dbl2big(double d)`
    ///
    /// Converts `d` to Bignum. Can raise `NoMemoryError` or `FloatDomainError`.
    #[doc(alias = "raising")]
    pub fn rb_dbl2big(d: c_double) -> VALUE;

    // ---- strings: include/ruby/internal/intern/string.h ----
    /// `VALUE rb_str_new(const char *ptr, long len)`
    ///
    /// Allocates a new Ruby String. Can raise `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_str_new(ptr: *const c_char, len: c_long) -> VALUE;

    /// `VALUE rb_str_new_cstr(const char *ptr)`
    ///
    /// Allocates a new Ruby String from a C string. Can raise `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_str_new_cstr(ptr: *const c_char) -> VALUE;

    /// `VALUE rb_usascii_str_new(const char *ptr, long len)`
    ///
    /// Allocates a new US-ASCII Ruby String. Can raise `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_usascii_str_new(ptr: *const c_char, len: c_long) -> VALUE;

    // ---- symbols and calls: include/ruby/internal/symbol.h, eval.h ----
    /// `ID rb_intern2(const char *name, long len)`
    ///
    /// Interns a string as a Symbol ID. Can raise `ArgumentError` or `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_intern2(name: *const c_char, len: c_long) -> ID;

    /// `VALUE rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv)`
    ///
    /// Invokes a Ruby method. Can raise any Ruby exception.
    #[doc(alias = "raising")]
    pub fn rb_funcallv(recv: VALUE, mid: ID, argc: c_int, argv: *const VALUE) -> VALUE;

    // ---- objects, arrays, hashes: intern/array.h, intern/hash.h ----
    /// `VALUE rb_ary_new(void)`
    ///
    /// Allocates a new Ruby Array. Can raise `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_ary_new() -> VALUE;

    /// `VALUE rb_ary_push(VALUE ary, VALUE elem)`
    ///
    /// Pushes `elem` onto `ary`. Can raise `FrozenError` or `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_ary_push(ary: VALUE, elem: VALUE) -> VALUE;

    /// `VALUE rb_hash_new(void)`
    ///
    /// Allocates a new Ruby Hash. Can raise `NoMemoryError`.
    #[doc(alias = "raising")]
    pub fn rb_hash_new() -> VALUE;

    /// `VALUE rb_hash_aref(VALUE hash, VALUE key)`
    ///
    /// Fetches key from `hash`. Can raise exceptions during key comparison/hash execution.
    #[doc(alias = "raising")]
    pub fn rb_hash_aref(hash: VALUE, key: VALUE) -> VALUE;

    /// `VALUE rb_hash_aset(VALUE hash, VALUE key, VALUE val)`
    ///
    /// Sets `key` to `val` in `hash`. Can raise `FrozenError` or key execution errors.
    #[doc(alias = "raising")]
    pub fn rb_hash_aset(hash: VALUE, key: VALUE, val: VALUE) -> VALUE;
}
