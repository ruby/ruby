//! Public C API of CRuby used by Wave B ports.
//!
//! Every declaration copies its prototype from `include/ruby/` (file named in
//! the comment).  C `long` is `c_long`, `intptr_t` is `isize`, `uintptr_t` is
//! `usize`, `LONG_LONG` is `c_longlong`.  Functions the header marks
//! `RBIMPL_ATTR_NORETURN()` return `!`.
//!
//! Declaring a function here creates no symbol: these are references to
//! `libruby`'s own definitions, and only the ones a port uses end up in
//! `core_rs.o`.  Only public API belongs here (AGENTS.md §6.7); see the
//! exception-safety rule in [`super`] before calling anything that can raise.
//!
//! `rb_protect()` and `rb_jump_tag()` are in [`super::protect`].

#![allow(non_upper_case_globals)]

use super::value::{ID, VALUE};
use core::ffi::{c_char, c_double, c_int, c_long, c_longlong, c_ulong, c_ulonglong};

unsafe extern "C" {
    // ---- exceptions: include/ruby/internal/error.h, intern/eval.h ----
    /// `void rb_raise(VALUE exc, const char *fmt, ...)`, noreturn.
    pub fn rb_raise(exc: VALUE, fmt: *const c_char, ...) -> !;
    /// `VALUE rb_errinfo(void)`
    pub fn rb_errinfo() -> VALUE;
    /// `void rb_set_errinfo(VALUE err)`
    pub fn rb_set_errinfo(err: VALUE);

    // ---- exception classes: include/ruby/internal/globals.h ----
    pub static rb_eArgError: VALUE;
    pub static rb_eTypeError: VALUE;
    pub static rb_eRangeError: VALUE;
    pub static rb_eRuntimeError: VALUE;
    pub static rb_eIndexError: VALUE;
    pub static rb_eFloatDomainError: VALUE;
    pub static rb_eZeroDivError: VALUE;
    pub static rb_eNotImpError: VALUE;

    // ---- numbers: include/ruby/internal/arithmetic/*.h, intern/bignum.h ----
    /// `long rb_num2long(VALUE num)`
    pub fn rb_num2long(num: VALUE) -> c_long;
    /// `unsigned long rb_num2ulong(VALUE num)`
    pub fn rb_num2ulong(num: VALUE) -> c_ulong;
    /// `double rb_num2dbl(VALUE num)`
    pub fn rb_num2dbl(num: VALUE) -> c_double;
    /// `VALUE rb_int2inum(intptr_t i)`
    pub fn rb_int2inum(i: isize) -> VALUE;
    /// `VALUE rb_uint2inum(uintptr_t i)`
    pub fn rb_uint2inum(i: usize) -> VALUE;
    /// `VALUE rb_ll2inum(LONG_LONG num)`
    pub fn rb_ll2inum(num: c_longlong) -> VALUE;
    /// `VALUE rb_ull2inum(unsigned LONG_LONG num)`
    pub fn rb_ull2inum(num: c_ulonglong) -> VALUE;
    /// `VALUE rb_dbl2big(double d)`
    pub fn rb_dbl2big(d: c_double) -> VALUE;
    /// `double rb_float_value(VALUE num)`
    pub fn rb_float_value(num: VALUE) -> c_double;

    // ---- strings: include/ruby/internal/intern/string.h ----
    /// `VALUE rb_str_new(const char *ptr, long len)`
    pub fn rb_str_new(ptr: *const c_char, len: c_long) -> VALUE;
    /// `VALUE rb_str_new_cstr(const char *ptr)`
    pub fn rb_str_new_cstr(ptr: *const c_char) -> VALUE;
    /// `VALUE rb_usascii_str_new(const char *ptr, long len)`
    pub fn rb_usascii_str_new(ptr: *const c_char, len: c_long) -> VALUE;

    // ---- symbols and calls: include/ruby/internal/symbol.h, eval.h ----
    /// `ID rb_intern2(const char *name, long len)`
    pub fn rb_intern2(name: *const c_char, len: c_long) -> ID;
    /// `VALUE rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv)`
    pub fn rb_funcallv(recv: VALUE, mid: ID, argc: c_int, argv: *const VALUE) -> VALUE;

    // ---- objects, arrays, hashes: intern/object.h, intern/array.h, intern/hash.h ----
    /// `VALUE rb_obj_class(VALUE obj)`
    pub fn rb_obj_class(obj: VALUE) -> VALUE;
    /// `VALUE rb_ary_new(void)`
    pub fn rb_ary_new() -> VALUE;
    /// `VALUE rb_ary_push(VALUE ary, VALUE elem)`
    pub fn rb_ary_push(ary: VALUE, elem: VALUE) -> VALUE;
    /// `VALUE rb_hash_new(void)`
    pub fn rb_hash_new() -> VALUE;
    /// `VALUE rb_hash_aref(VALUE hash, VALUE key)`
    pub fn rb_hash_aref(hash: VALUE, key: VALUE) -> VALUE;
    /// `VALUE rb_hash_aset(VALUE hash, VALUE key, VALUE val)`
    pub fn rb_hash_aset(hash: VALUE, key: VALUE, val: VALUE) -> VALUE;

    // ---- memory: include/ruby/internal/xmalloc.h ----
    /// `void *ruby_xmalloc(size_t size)`
    pub fn ruby_xmalloc(size: usize) -> *mut core::ffi::c_void;
    /// `void *ruby_xrealloc(void *ptr, size_t newsiz)`
    pub fn ruby_xrealloc(ptr: *mut core::ffi::c_void, newsiz: usize) -> *mut core::ffi::c_void;
    /// `void ruby_xfree(void *ptr)`
    pub fn ruby_xfree(ptr: *mut core::ffi::c_void);
}
