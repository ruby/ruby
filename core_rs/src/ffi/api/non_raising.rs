//! Non-raising C API declarations of CRuby.
//!
//! Functions and global variables in this module are guaranteed never to raise
//! Ruby exceptions or trigger `longjmp` non-local unwinding. They are safe to call
//! directly from Rust code without `protect()` or special stack frame destructor
//! restrictions.

#![allow(non_upper_case_globals)]

use crate::ffi::value::VALUE;
use core::ffi::{c_double, c_longlong, c_ulonglong};

unsafe extern "C" {
    // ---- exceptions: include/ruby/internal/error.h, intern/eval.h ----
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
    /// `VALUE rb_int2inum(intptr_t i)`
    pub fn rb_int2inum(i: isize) -> VALUE;
    /// `VALUE rb_uint2inum(uintptr_t i)`
    pub fn rb_uint2inum(i: usize) -> VALUE;
    /// `VALUE rb_ll2inum(LONG_LONG num)`
    pub fn rb_ll2inum(num: c_longlong) -> VALUE;
    /// `VALUE rb_ull2inum(unsigned LONG_LONG num)`
    pub fn rb_ull2inum(num: c_ulonglong) -> VALUE;
    /// `double rb_float_value(VALUE num)`
    pub fn rb_float_value(num: VALUE) -> c_double;

    // ---- objects: intern/object.h ----
    /// `VALUE rb_obj_class(VALUE obj)`
    pub fn rb_obj_class(obj: VALUE) -> VALUE;

    // ---- memory: include/ruby/internal/xmalloc.h ----
    /// `void ruby_xfree(void *ptr)`
    pub fn ruby_xfree(ptr: *mut core::ffi::c_void);
}
