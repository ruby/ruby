//! Shared code between YJIT and ZJIT.
#![warn(unsafe_op_in_unsafe_fn)] // Adopt 2024 edition default when targeting 2021 editions

use std::sync::atomic::{AtomicUsize, Ordering};
use std::alloc::{GlobalAlloc, Layout, System};
use std::ffi::CStr;
use std::os::raw::{c_int, c_uint};
use std::panic::{catch_unwind, AssertUnwindSafe};

#[global_allocator]
pub static GLOBAL_ALLOCATOR: StatsAlloc = StatsAlloc { alloc_size: AtomicUsize::new(0) };

pub struct StatsAlloc {
    pub alloc_size: AtomicUsize,
}

unsafe impl GlobalAlloc for StatsAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        self.alloc_size.fetch_add(layout.size(), Ordering::SeqCst);
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        self.alloc_size.fetch_sub(layout.size(), Ordering::SeqCst);
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        self.alloc_size.fetch_add(layout.size(), Ordering::SeqCst);
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if new_size > layout.size() {
            self.alloc_size.fetch_add(new_size - layout.size(), Ordering::SeqCst);
        } else if new_size < layout.size() {
            self.alloc_size.fetch_sub(layout.size() - new_size, Ordering::SeqCst);
        }
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

/// How a JIT takes and releases the VM lock and its barrier, for [with_vm_lock_lazy_barrier].
pub trait VmLockOps: Default {
    const JIT_NAME: &'static str;
    fn lock(recursive_lock_level: &mut c_uint, file: &CStr, line: c_int);
    fn unlock(recursive_lock_level: &mut c_uint, file: &CStr, line: c_int);
    fn take_barrier(&mut self);
    /// Undo JIT-specific work done in [VmLockOps::take_barrier] before the VM lock is released.
    fn release_barrier(&mut self) {}
}

/// The VM lock held while running [with_vm_lock_lazy_barrier]'s closure.
pub struct VmLock<O: VmLockOps> {
    barrier: bool,
    ops: O,
}

impl<O: VmLockOps> VmLock<O> {
    /// Stop other Ractors so code can be patched. Releases the VM lock while waiting for
    /// them, so recheck anything read under it before this call.
    pub fn take_barrier(&mut self) {
        if !self.barrier {
            self.ops.take_barrier();
            self.barrier = true;
        }
    }
}

/// Acquire the VM lock without stopping other Ractors and run `func`. Enough to read or
/// update JIT bookkeeping guarded by the VM lock; `func` must call [VmLock::take_barrier]
/// before patching code.
pub fn with_vm_lock_lazy_barrier<O, F, R>(file: &CStr, line: c_int, func: F) -> R
where
    O: VmLockOps,
    F: FnOnce(&mut VmLock<O>) -> R,
{
    let mut recursive_lock_level: c_uint = 0;

    O::lock(&mut recursive_lock_level, file, line);
    let mut lock = VmLock { barrier: false, ops: O::default() };

    let ret = match catch_unwind(AssertUnwindSafe(|| func(&mut lock))) {
        Ok(result) => result,
        Err(_) => {
            // Theoretically we can recover from some of these panics,
            // but it's too late if the unwind reaches here.

            let _ = catch_unwind(|| {
                // IO functions can panic too.
                eprintln!(
                    "{} panicked while holding VM lock acquired at {}:{}. Aborting...",
                    O::JIT_NAME,
                    file.to_string_lossy(),
                    line,
                );
            });
            std::process::abort();
        }
    };

    if lock.barrier {
        lock.ops.release_barrier();
    }
    O::unlock(&mut recursive_lock_level, file, line);

    ret
}
