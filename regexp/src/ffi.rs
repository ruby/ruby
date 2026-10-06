//! Functions exported to C. Every symbol is named `rb_regexp_rust_*` because
//! the partial link of the Rust static library keeps only `rb_*` globals.
//!
//! No Ruby code runs while Rust frames are on the stack: warnings are
//! collected during compilation and handed back to C, which emits them after
//! the call returns. A raise from `Warning.warn` therefore never unwinds
//! through Rust.

#![allow(unsafe_code)]

use std::cell::RefCell;
use std::ffi::{c_char, c_int};
use std::panic::{self, AssertUnwindSafe};
use std::sync::{Arc, Mutex};

use crate::compile::{self, Regex};
use crate::enc::{self, Enc, OnigEncodingType};
use crate::error::*;
use crate::parser::{self, Warner};

/// Version of the interface between this crate and `re_engine.c`. The C side
/// refuses to use the engine when its own copy of the number differs.
pub const ABI_VERSION: u32 = 2;

#[unsafe(no_mangle)]
pub extern "C" fn rb_regexp_rust_abi_version() -> u32 {
    ABI_VERSION
}

thread_local! {
    static PANIC_MESSAGE: RefCell<Option<String>> = const { RefCell::new(None) };
}

/// Runs `f`, turning a panic into `on_panic` and remembering its message
/// for `rb_regexp_rust_take_panic_message`. Unwinding out of an
/// `extern "C"` function aborts the process, so every export goes through
/// here.
fn guard<T>(on_panic: T, f: impl FnOnce() -> T) -> T {
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            PANIC_MESSAGE.with(|m| *m.borrow_mut() = Some(msg));
            on_panic
        }
    }
}

/// Copies the message of the last panic on this thread into `buf` as a
/// NUL-terminated string and clears it. Returns 0 when there was none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_take_panic_message(buf: *mut c_char, len: usize) -> c_int {
    let msg = PANIC_MESSAGE.with(|m| m.borrow_mut().take());
    match msg {
        Some(msg) if len > 0 && !buf.is_null() => {
            let n = msg.len().min(len - 1);
            unsafe {
                std::ptr::copy_nonoverlapping(msg.as_ptr(), buf as *mut u8, n);
                *buf.add(n) = 0;
            }
            1
        }
        Some(_) => 1,
        None => 0,
    }
}

/// Registers `OnigEncodingASCII`, used to resolve the property names of
/// `\X` the same way regparse.c does.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_init(ascii: *const OnigEncodingType) {
    if !ascii.is_null() {
        enc::set_ascii(unsafe { Enc::from_ptr(ascii) });
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_regexp_rust_get_parse_depth_limit() -> u32 {
    parser::get_parse_depth_limit()
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_regexp_rust_set_parse_depth_limit(depth: u32) -> c_int {
    parser::set_parse_depth_limit(depth);
    0
}

/// The engine's handle, `rb_regexp_rust_t` in C.
pub struct Handle {
    pub primary: Arc<Regex>,
    pub source: Vec<u8>,
    pub options: u32,
    /// Compiled for other encodings of the subject string; see re_engine.c.
    pub variants: Mutex<Vec<(Enc, Arc<Regex>)>>,
}

pub const RB_REGEXP_WARN_ENABLED: c_int = 1;
pub const RB_REGEXP_WARN_VERBOSE: c_int = 2;

/// `struct rb_regexp_compile_result`
#[repr(C)]
pub struct CompileResult {
    pub code: c_int,
    /// `onig_errmsg_buffer`, NUL-terminated.
    pub message: [u8; ONIG_MAX_ERROR_MESSAGE_LEN],
    /// Warning messages, each terminated by NUL. Free with
    /// `rb_regexp_rust_free_bytes`.
    pub warnings: *mut u8,
    pub warnings_len: usize,
}

struct CollectWarner {
    flags: c_int,
    out: Vec<u8>,
}

impl Warner for CollectWarner {
    fn enabled(&self) -> bool {
        self.flags & RB_REGEXP_WARN_ENABLED != 0
    }
    fn verbose(&self) -> bool {
        self.flags & RB_REGEXP_WARN_VERBOSE != 0
    }
    fn warn(&mut self, msg: &[u8]) {
        self.out.extend(msg.iter().copied().filter(|&b| b != 0));
        self.out.push(0);
    }
}

fn leak_bytes(v: Vec<u8>) -> (*mut u8, usize) {
    if v.is_empty() {
        return (std::ptr::null_mut(), 0);
    }
    let b = v.into_boxed_slice();
    let len = b.len();
    (Box::into_raw(b) as *mut u8, len)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

/// Returns the number of bytes copied before the NUL.
fn write_message(dst: &mut [u8; ONIG_MAX_ERROR_MESSAGE_LEN], msg: &[u8]) -> usize {
    let n = msg.len().min(dst.len() - 1);
    dst[..n].copy_from_slice(&msg[..n]);
    dst[n] = 0;
    n
}

/// Compiles `pat` with the Ruby syntax and the default case fold flag
/// (`onig_new` with `ONIG_SYNTAX_RUBY`). Returns 0 and sets `*out`, or
/// returns an error code and fills `res->message`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_compile(
    pat: *const u8,
    len: usize,
    options: u32,
    enc: *const OnigEncodingType,
    warn_flags: c_int,
    out: *mut *mut Handle,
    res: *mut CompileResult,
) -> c_int {
    let source: &[u8] = if len == 0 { &[] } else { unsafe { std::slice::from_raw_parts(pat, len) } };
    let enc = unsafe { Enc::from_ptr(enc) };
    let res = unsafe { &mut *res };
    let out = unsafe { &mut *out };
    *out = std::ptr::null_mut();
    res.code = 0;
    res.message[0] = 0;
    res.warnings = std::ptr::null_mut();
    res.warnings_len = 0;

    let mut warner = CollectWarner { flags: warn_flags, out: Vec::new() };
    let compiled = guard(Err(RB_REGEXP_PANICKED), || {
        compile::compile(source, options, enc::ONIGENC_CASE_FOLD_MIN, enc, &mut warner).map_err(|e| {
            let msg = error_code_to_str(e.code, e.par.as_deref().map(|p| (enc, p)));
            write_message(&mut res.message, &msg);
            e.code
        })
    });
    let code = match compiled {
        Ok(regex) => {
            *out = Box::into_raw(Box::new(Handle {
                primary: Arc::new(regex),
                source: source.to_vec(),
                options,
                variants: Mutex::new(Vec::new()),
            }));
            0
        }
        Err(code) => code,
    };
    let (w, wl) = leak_bytes(std::mem::take(&mut warner.out));
    res.warnings = w;
    res.warnings_len = wl;
    res.code = code;
    code
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_free(h: *mut Handle) {
    if !h.is_null() {
        // Dropping only frees memory, so this cannot panic in practice.
        drop(unsafe { Box::from_raw(h) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_num_mem(h: *const Handle) -> c_int {
    let h = unsafe { &*h };
    h.primary.num_mem
}

/// Formats an error code the way `onig_error_code_to_str` does, for codes
/// raised outside compilation (match errors).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_error_str(buf: *mut u8, code: c_int) -> c_int {
    let buf = unsafe { &mut *(buf as *mut [u8; ONIG_MAX_ERROR_MESSAGE_LEN]) };
    guard(RB_REGEXP_PANICKED, || write_message(buf, &error_code_to_str(code, None)) as c_int)
}

/// `struct rb_regexp_rust_info`: the compiled form, for comparing the two
/// engines in tests. Pointers stay valid while the handle lives.
#[repr(C)]
pub struct Info {
    pub num_mem: c_int,
    pub num_repeat: c_int,
    pub num_null_check: c_int,
    pub num_call: c_int,
    pub capture_history: u32,
    pub bt_mem_start: u32,
    pub bt_mem_end: u32,
    pub stack_pop_level: c_int,
    pub options: u32,
    pub optimize: c_int,
    pub threshold_len: c_int,
    pub anchor: c_int,
    pub anchor_dmin: usize,
    pub anchor_dmax: usize,
    pub sub_anchor: c_int,
    pub dmin: usize,
    pub dmax: usize,
    pub program: *const u8,
    pub program_len: usize,
    pub exact: *const u8,
    pub exact_len: usize,
    pub map: *const u8,
    /// lower, upper pairs
    pub repeat_range: *const c_int,
    pub repeat_range_len: usize,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_info(h: *const Handle, info: *mut Info) {
    let r: &Regex = unsafe { &(*h).primary };
    let info = unsafe { &mut *info };
    *info = Info {
        num_mem: r.num_mem,
        num_repeat: r.num_repeat,
        num_null_check: r.num_null_check,
        num_call: r.num_call,
        capture_history: r.capture_history,
        bt_mem_start: r.bt_mem_start,
        bt_mem_end: r.bt_mem_end,
        stack_pop_level: r.stack_pop_level,
        options: r.options,
        optimize: r.optimize,
        threshold_len: r.threshold_len,
        anchor: r.anchor,
        anchor_dmin: r.anchor_dmin,
        anchor_dmax: r.anchor_dmax,
        sub_anchor: r.sub_anchor,
        dmin: r.dmin,
        dmax: r.dmax,
        program: r.program.as_ptr(),
        program_len: r.program.len(),
        exact: r.exact.as_ptr(),
        exact_len: r.exact.len(),
        map: r.map.as_ptr(),
        repeat_range: r.repeat_range.as_ptr() as *const c_int,
        repeat_range_len: r.repeat_range.len(),
    };
}

/// The number of named groups. With `rb_regexp_rust_name_at` this lets C
/// walk the names itself: a callback that builds Ruby objects could raise
/// and unwind through Rust.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_name_count(h: *const Handle) -> usize {
    let h = unsafe { &*h };
    h.primary.names.len()
}

/// The `i`-th named group in definition order. Pointers stay valid while
/// the handle lives. Returns 0 when `i` is out of range.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_regexp_rust_name_at(
    h: *const Handle,
    i: usize,
    name: *mut *const u8,
    name_len: *mut usize,
    ngroups: *mut c_int,
    groups: *mut *const c_int,
) -> c_int {
    let r: &Regex = unsafe { &(*h).primary };
    match r.names.entries().get(i) {
        Some(e) => {
            unsafe {
                *name = e.name.as_ptr();
                *name_len = e.name.len();
                *ngroups = e.back_refs.len() as c_int;
                *groups = e.back_refs.as_ptr();
            }
            1
        }
        None => 0,
    }
}
