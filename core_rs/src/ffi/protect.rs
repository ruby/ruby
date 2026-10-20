//! `rb_protect()` and `rb_jump_tag()` for Rust callers.
//!
//! The C idiom
//!
//! ```c
//! int state = 0;
//! VALUE ret = rb_protect(func, arg, &state);
//! /* cleanup */
//! if (state) rb_jump_tag(state);
//! ```
//!
//! is written in a port as
//!
//! ```ignore
//! let ret = unsafe { protect(|| /* raising calls */ Qnil) };
//! /* cleanup */
//! let ret = match ret { Ok(v) => v, Err(state) => unsafe { jump_tag(state) } };
//! ```
//!
//! The closure must be `Copy`, so it cannot own a value with a destructor:
//! when the code inside raises, the frames of the closure and of the
//! trampoline below are discarded by `longjmp()` (see the exception-safety
//! rule in [`super`]).  The same rule applies to the closure's own body.

use super::value::VALUE;
use core::ffi::c_int;

#[cfg(not(test))]
unsafe extern "C" {
    // include/ruby/internal/intern/proc.h
    /// `VALUE rb_protect(VALUE (*func)(VALUE args), VALUE args, int *state)`
    pub fn rb_protect(func: extern "C" fn(VALUE) -> VALUE, args: VALUE, state: *mut c_int)
        -> VALUE;
    // include/ruby/internal/intern/eval.h
    /// `void rb_jump_tag(int state)`, noreturn.
    pub fn rb_jump_tag(state: c_int) -> !;
}

#[cfg(test)]
use self::mock::{rb_jump_tag, rb_protect};

/// Calls `f` under `rb_protect()`.
///
/// Returns `Ok(value)` when `f` returned normally and `Err(state)` when it
/// left by a non-local exit (exception, `throw`, `break`, ...).  After an
/// `Err`, the pending exception is in `rb_errinfo()`: either re-raise it with
/// [`jump_tag`] or discard it with `rb_set_errinfo(Qnil)`, exactly as the C
/// being ported does.
///
/// # Safety
/// Must be called on a Ruby thread holding the GVL, as `rb_protect()`.
/// `f` must follow the exception-safety rule of [`super`].
pub unsafe fn protect<F>(f: F) -> Result<VALUE, c_int>
where
    F: FnOnce() -> VALUE + Copy,
{
    extern "C" fn trampoline<F: FnOnce() -> VALUE + Copy>(arg: VALUE) -> VALUE {
        // SAFETY: `arg` is the address of `f` in `protect` below, which
        // outlives the rb_protect() call that invokes this trampoline.
        let f = unsafe { *(arg as *const F) };
        f()
    }

    let mut state: c_int = 0;
    // SAFETY: the caller guarantees the GVL; `trampoline::<F>` reads `f`
    // through the pointer only while `f` is alive; `state` is a valid int.
    let ret = unsafe { rb_protect(trampoline::<F>, &f as *const F as VALUE, &mut state) };
    if state == 0 { Ok(ret) } else { Err(state) }
}

/// Resumes the non-local exit recorded by [`protect`] (`rb_jump_tag()`).
///
/// # Safety
/// `state` must be an `Err` value returned by [`protect`] on this thread,
/// and no Rust frame up to the C caller may hold a `Drop` value.
pub unsafe fn jump_tag(state: c_int) -> ! {
    // SAFETY: forwarded from the caller.
    unsafe { rb_jump_tag(state) }
}

/// Calls `f` under `rb_protect()`, invoking `cleanup` before re-raising if an
/// exception or non-local exit occurs.
///
/// If `f` returns normally, `protect_with_cleanup` returns its `VALUE`.
/// If `f` leaves by a non-local exit (`Err(state)`), `cleanup` is executed and
/// then [`jump_tag(state)`] re-raises the exception.
///
/// # Safety
/// Must be called on a Ruby thread holding the GVL, as `rb_protect()`.
/// `f` must follow the exception-safety rule of [`super`].
pub unsafe fn protect_with_cleanup<F, C>(f: F, cleanup: C) -> VALUE
where
    F: FnOnce() -> VALUE + Copy,
    C: FnOnce(),
{
    match unsafe { protect(f) } {
        Ok(val) => val,
        Err(state) => {
            cleanup();
            // SAFETY: `state` is a non-zero jump tag from `protect(f)`.
            unsafe { jump_tag(state) };
        }
    }
}

/// Concise macro for executing a raising expression under `rb_protect()`.
///
/// If the call completes normally, its `VALUE` is returned. If an exception or
/// non-local exit occurs, any optional cleanup closure is executed before
/// re-raising via [`jump_tag`].
///
/// # Examples
///
/// ```ignore
/// let val = protect_call!(rb_funcallv(recv, id, argc, argv));
///
/// let val = protect_call!(rb_num2long(raw), || cleanup_local_state());
/// ```
#[macro_export]
macro_rules! protect_call {
    ($expr:expr) => {
        match unsafe { $crate::ffi::protect::protect(|| $expr) } {
            Ok(val) => val,
            Err(state) => unsafe { $crate::ffi::protect::jump_tag(state) },
        }
    };
    ($expr:expr, $cleanup:expr) => {
        unsafe { $crate::ffi::protect::protect_with_cleanup(|| $expr, $cleanup) }
    };
}

pub use protect_call;

/// Stand-ins for the two C functions, for `make core-rs-test` (which links
/// no libruby).  They model only the observable contract `protect` relies
/// on: `func(args)` is called once, and `*state` is 0 on a normal return or
/// the tag of a non-local exit, in which case the return value is `Qnil`.
/// A test makes the "C" side raise by setting `RAISE_TAG` before the call.
#[cfg(test)]
mod mock {
    use super::super::value::{Qnil, VALUE};
    use core::ffi::c_int;
    use std::cell::Cell;

    std::thread_local! {
        pub static RAISE_TAG: Cell<c_int> = const { Cell::new(0) };
        pub static CALLS: Cell<u32> = const { Cell::new(0) };
    }

    pub unsafe fn rb_protect(
        func: extern "C" fn(VALUE) -> VALUE,
        args: VALUE,
        state: *mut c_int,
    ) -> VALUE {
        CALLS.with(|c| c.set(c.get() + 1));
        let ret = func(args);
        let tag = RAISE_TAG.with(|t| t.replace(0));
        // SAFETY: `state` points at protect()'s local.
        unsafe { *state = tag };
        if tag == 0 { ret } else { Qnil }
    }

    pub unsafe fn rb_jump_tag(state: c_int) -> ! {
        panic!("rb_jump_tag({state})");
    }
}

#[cfg(test)]
mod tests {
    use super::mock::{CALLS, RAISE_TAG};
    use super::*;
    use crate::ffi::value::{INT2FIX, Qnil};

    #[test]
    fn normal_return_passes_the_value_through() {
        let x = 20;
        let before = CALLS.with(|c| c.get());
        let r = unsafe { protect(|| INT2FIX(x + 1)) };
        assert_eq!(r, Ok(INT2FIX(21)));
        assert_eq!(CALLS.with(|c| c.get()), before + 1);
    }

    #[test]
    fn closure_reads_captured_references() {
        let buf = [1u8, 2, 3, 4];
        let r = unsafe { protect(|| INT2FIX(buf.iter().map(|&b| b as i64).sum())) };
        assert_eq!(r, Ok(INT2FIX(10)));
    }

    #[test]
    fn non_local_exit_returns_its_state() {
        // TAG_RAISE is 6 in vm_core.h.
        let r = unsafe {
            protect(|| {
                RAISE_TAG.with(|t| t.set(6));
                INT2FIX(1)
            })
        };
        assert_eq!(r, Err(6));
        // The next call is unaffected.
        assert_eq!(unsafe { protect(|| Qnil) }, Ok(Qnil));
    }

    #[test]
    #[should_panic(expected = "rb_jump_tag(6)")]
    fn jump_tag_forwards_the_state() {
        unsafe { jump_tag(6) }
    }

    #[test]
    fn protect_with_cleanup_normal_return_returns_value_without_cleanup() {
        let mut cleaned = false;
        let r = unsafe { protect_with_cleanup(|| INT2FIX(42), || cleaned = true) };
        assert_eq!(r, INT2FIX(42));
        assert!(!cleaned);
    }

    #[test]
    #[should_panic(expected = "rb_jump_tag(6)")]
    fn protect_with_cleanup_exception_executes_cleanup_then_jumps() {
        use std::cell::Cell;
        std::thread_local! {
            static CLEANUP_RAN: Cell<bool> = const { Cell::new(false) };
        }

        struct CheckCleanup;
        impl Drop for CheckCleanup {
            fn drop(&mut self) {
                assert!(CLEANUP_RAN.with(|c| c.get()), "cleanup closure should have been executed before jump_tag panic");
            }
        }

        let _check = CheckCleanup;
        unsafe {
            protect_with_cleanup(
                || {
                    RAISE_TAG.with(|t| t.set(6));
                    INT2FIX(1)
                },
                || {
                    CLEANUP_RAN.with(|c| c.set(true));
                },
            );
        }
    }

    #[test]
    fn protect_call_macro_normal_return() {
        let v = protect_call!(INT2FIX(100));
        assert_eq!(v, INT2FIX(100));

        let mut cleaned = false;
        let v2 = protect_call!(INT2FIX(200), || cleaned = true);
        assert_eq!(v2, INT2FIX(200));
        assert!(!cleaned);
    }

    #[test]
    #[should_panic(expected = "rb_jump_tag(6)")]
    fn protect_call_macro_exception_re_raised() {
        protect_call!({
            RAISE_TAG.with(|t| t.set(6));
            INT2FIX(1)
        });
    }

    #[test]
    #[should_panic(expected = "rb_jump_tag(6)")]
    fn protect_call_macro_exception_executes_cleanup_and_re_raises() {
        use std::cell::Cell;
        std::thread_local! {
            static MACRO_CLEANUP_RAN: Cell<bool> = const { Cell::new(false) };
        }

        struct CheckMacroCleanup;
        impl Drop for CheckMacroCleanup {
            fn drop(&mut self) {
                assert!(MACRO_CLEANUP_RAN.with(|c| c.get()), "macro cleanup closure should have executed before jump_tag panic");
            }
        }

        let _check = CheckMacroCleanup;
        protect_call!(
            {
                RAISE_TAG.with(|t| t.set(6));
                INT2FIX(1)
            },
            || {
                MACRO_CLEANUP_RAN.with(|c| c.set(true));
            }
        );
    }
}
