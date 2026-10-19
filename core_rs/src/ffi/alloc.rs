//! Safe FFI Allocator Wrapper around Ruby GC Memory Allocation.
//!
//! Provides safe memory allocation primitives and collection types (`GcByteBuffer`)
//! that interface with Ruby's `ruby_xmalloc`, `ruby_xrealloc`, and `ruby_xfree`.
//!
//! # Exception Safety
//! Ruby's `ruby_xmalloc` and `ruby_xrealloc` may raise a Ruby `NoMemoryError`
//! via `longjmp` on allocation failure. Calls that can raise must follow the
//! exception-safety rules described in [`super`].

use super::api;
use core::ffi::c_void;
use core::ops::{Deref, DerefMut};

/// Allocates `size` bytes using Ruby GC allocator (`ruby_xmalloc`).
///
/// # Safety
/// Caller must follow exception-safety rules (no live `Drop` values across call
/// unless protected or unwinding is handled).
#[inline]
pub unsafe fn xmalloc(size: usize) -> *mut u8 {
    unsafe { api::ruby_xmalloc(size) as *mut u8 }
}

/// Reallocates a pointer to `newsiz` bytes using Ruby GC allocator (`ruby_xrealloc`).
///
/// # Safety
/// `ptr` must be null or a valid pointer previously allocated with `xmalloc` / `xrealloc`.
#[inline]
pub unsafe fn xrealloc(ptr: *mut u8, newsiz: usize) -> *mut u8 {
    unsafe { api::ruby_xrealloc(ptr as *mut c_void, newsiz) as *mut u8 }
}

/// Frees memory allocated by Ruby GC allocator (`ruby_xfree`).
///
/// If `ptr` is null, this is a safe no-op.
#[inline]
pub unsafe fn xfree(ptr: *mut u8) {
    if !ptr.is_null() {
        unsafe { api::ruby_xfree(ptr as *mut c_void) };
    }
}

/// Allocates memory for a single value of type `T` using `ruby_xmalloc`.
///
/// # Safety
/// Caller must ensure `T` layout constraints and exception safety.
#[inline]
pub unsafe fn xmalloc_typed<T>() -> *mut T {
    unsafe { xmalloc(core::mem::size_of::<T>()) as *mut T }
}

/// Allocates memory for `len` elements of type `T` using `ruby_xmalloc`.
///
/// # Safety
/// Caller must handle alignment, type constraints, and potential arithmetic overflow.
#[inline]
pub unsafe fn xmalloc_array<T>(len: usize) -> *mut T {
    let size = len.checked_mul(core::mem::size_of::<T>()).expect("allocation size overflow");
    unsafe { xmalloc(size) as *mut T }
}

/// Reallocates an array buffer of `T` to `new_len` elements using `ruby_xrealloc`.
///
/// # Safety
/// `ptr` must be a pointer allocated via `xmalloc` or null.
#[inline]
pub unsafe fn xrealloc_array<T>(ptr: *mut T, new_len: usize) -> *mut T {
    let size = new_len.checked_mul(core::mem::size_of::<T>()).expect("allocation size overflow");
    unsafe { xrealloc(ptr as *mut u8, size) as *mut T }
}

/// Frees a typed allocation created via Ruby GC allocator (`ruby_xfree`).
#[inline]
pub unsafe fn xfree_typed<T>(ptr: *mut T) {
    unsafe { xfree(ptr as *mut u8) };
}

/// A dynamic byte buffer allocated via Ruby's GC-aware memory functions (`ruby_xmalloc`, `ruby_xrealloc`, `ruby_xfree`).
///
/// `GcByteBuffer` automatically frees its backing storage when dropped unless ownership
/// is transferred via [`into_raw_parts`].
pub struct GcByteBuffer {
    ptr: *mut u8,
    cap: usize,
    len: usize,
}

impl GcByteBuffer {
    /// Creates a new, empty `GcByteBuffer`.
    #[inline]
    pub const fn new() -> Self {
        Self {
            ptr: core::ptr::null_mut(),
            cap: 0,
            len: 0,
        }
    }

    /// Creates a new `GcByteBuffer` pre-allocated with the specified capacity.
    pub fn with_capacity(cap: usize) -> Self {
        let mut buf = Self::new();
        if cap > 0 {
            buf.reserve(cap);
        }
        buf
    }

    /// Returns the capacity of the buffer in bytes.
    #[inline]
    pub const fn capacity(&self) -> usize {
        self.cap
    }

    /// Returns the number of bytes in the buffer.
    #[inline]
    pub const fn len(&self) -> usize {
        self.len
    }

    /// Returns `true` if the buffer contains no bytes.
    #[inline]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Returns a slice of the buffer's contents.
    #[inline]
    pub fn as_slice(&self) -> &[u8] {
        if self.ptr.is_null() || self.len == 0 {
            &[]
        } else {
            unsafe { core::slice::from_raw_parts(self.ptr, self.len) }
        }
    }

    /// Returns a mutable slice of the buffer's contents.
    #[inline]
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        if self.ptr.is_null() || self.len == 0 {
            &mut []
        } else {
            unsafe { core::slice::from_raw_parts_mut(self.ptr, self.len) }
        }
    }

    /// Returns a raw pointer to the buffer's memory.
    #[inline]
    pub const fn as_ptr(&self) -> *const u8 {
        self.ptr
    }

    /// Returns a raw mutable pointer to the buffer's memory.
    #[inline]
    pub fn as_mut_ptr(&mut self) -> *mut u8 {
        self.ptr
    }

    /// Reserves capacity for at least `additional` more bytes.
    pub fn reserve(&mut self, additional: usize) {
        let required = self.len.checked_add(additional).expect("capacity overflow");
        if required <= self.cap {
            return;
        }

        let mut new_cap = if self.cap == 0 { 8 } else { self.cap * 2 };
        if new_cap < required {
            new_cap = required;
        }

        let new_ptr = if self.ptr.is_null() {
            unsafe { xmalloc(new_cap) }
        } else {
            unsafe { xrealloc(self.ptr, new_cap) }
        };

        self.ptr = new_ptr;
        self.cap = new_cap;
    }

    /// Appends a byte to the end of the buffer.
    pub fn push(&mut self, byte: u8) {
        if self.len == self.cap {
            self.reserve(1);
        }
        unsafe {
            *self.ptr.add(self.len) = byte;
        }
        self.len += 1;
    }

    /// Appends a slice of bytes to the buffer.
    pub fn extend_from_slice(&mut self, slice: &[u8]) {
        if slice.is_empty() {
            return;
        }
        self.reserve(slice.len());
        unsafe {
            core::ptr::copy_nonoverlapping(slice.as_ptr(), self.ptr.add(self.len), slice.len());
        }
        self.len += slice.len();
    }

    /// Clears the buffer, setting length to 0 while keeping allocated capacity.
    #[inline]
    pub fn clear(&mut self) {
        self.len = 0;
    }

    /// Truncates the buffer to `len` bytes.
    #[inline]
    pub fn truncate(&mut self, len: usize) {
        if len < self.len {
            self.len = len;
        }
    }

    /// Sets the length of the buffer directly.
    ///
    /// # Safety
    /// `new_len` must be less than or equal to `capacity()`, and elements up to `new_len`
    /// must be valid initialized bytes.
    #[inline]
    pub unsafe fn set_len(&mut self, new_len: usize) {
        debug_assert!(new_len <= self.cap);
        self.len = new_len;
    }

    /// Deconstructs the buffer into its raw components `(ptr, len, cap)`.
    ///
    /// Memory ownership is transferred to the caller and `Drop` will not run.
    #[inline]
    pub fn into_raw_parts(self) -> (*mut u8, usize, usize) {
        let parts = (self.ptr, self.len, self.cap);
        core::mem::forget(self);
        parts
    }

    /// Reconstructs a `GcByteBuffer` from raw parts previously obtained from [`into_raw_parts`].
    ///
    /// # Safety
    /// `ptr` must be null or point to memory allocated with Ruby GC allocator (`ruby_xmalloc`/`ruby_xrealloc`),
    /// `cap` must be the allocated capacity, and `len <= cap`.
    #[inline]
    pub unsafe fn from_raw_parts(ptr: *mut u8, len: usize, cap: usize) -> Self {
        Self { ptr, len, cap }
    }
}

impl Default for GcByteBuffer {
    fn default() -> Self {
        Self::new()
    }
}

impl Deref for GcByteBuffer {
    type Target = [u8];

    #[inline]
    fn deref(&self) -> &[u8] {
        self.as_slice()
    }
}

impl DerefMut for GcByteBuffer {
    #[inline]
    fn deref_mut(&mut self) -> &mut [u8] {
        self.as_mut_slice()
    }
}

impl Drop for GcByteBuffer {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe { xfree(self.ptr) };
            self.ptr = core::ptr::null_mut();
            self.cap = 0;
            self.len = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ffi::api::mock::{ALLOC_COUNT, FREE_COUNT};
    use core::sync::atomic::Ordering;

    #[test]
    fn alloc_raw_primitives() {
        unsafe {
            let p = xmalloc(64);
            assert!(!p.is_null());
            *p = 42;
            let p2 = xrealloc(p, 128);
            assert!(!p2.is_null());
            assert_eq!(*p2, 42);
            xfree(p2);
            xfree(core::ptr::null_mut()); // No-op
        }
    }

    #[test]
    fn alloc_typed_primitives() {
        #[repr(C)]
        struct Point {
            x: i32,
            y: i32,
        }

        unsafe {
            let pt = xmalloc_typed::<Point>();
            assert!(!pt.is_null());
            (*pt).x = 10;
            (*pt).y = 20;
            assert_eq!((*pt).x, 10);
            assert_eq!((*pt).y, 20);
            xfree_typed(pt);

            let arr = xmalloc_array::<i32>(5);
            for i in 0..5 {
                *arr.add(i) = (i * 10) as i32;
            }
            let arr2 = xrealloc_array(arr, 10);
            for i in 0..5 {
                assert_eq!(*arr2.add(i), (i * 10) as i32);
            }
            xfree_typed(arr2);
        }
    }

    #[test]
    fn gc_byte_buffer_basic() {
        let mut buf = GcByteBuffer::new();
        assert_eq!(buf.len(), 0);
        assert_eq!(buf.capacity(), 0);
        assert!(buf.is_empty());
        assert_eq!(buf.as_slice(), &[]);

        buf.push(0x41);
        buf.push(0x42);
        buf.push(0x43);

        assert_eq!(buf.len(), 3);
        assert!(buf.capacity() >= 3);
        assert!(!buf.is_empty());
        assert_eq!(&buf[..], b"ABC");

        buf[1] = 0x78; // 'x'
        assert_eq!(&buf[..], b"AxC");

        buf.clear();
        assert_eq!(buf.len(), 0);
        assert!(buf.capacity() >= 3);
    }

    #[test]
    fn gc_byte_buffer_extend_and_realloc() {
        let mut buf = GcByteBuffer::with_capacity(4);
        assert!(buf.capacity() >= 4);

        buf.extend_from_slice(b"Hello, World!");
        assert_eq!(&buf[..], b"Hello, World!");
        assert_eq!(buf.len(), 13);

        buf.truncate(5);
        assert_eq!(&buf[..], b"Hello");
        assert_eq!(buf.len(), 5);
    }

    #[test]
    fn gc_byte_buffer_raw_parts() {
        let mut buf = GcByteBuffer::new();
        buf.extend_from_slice(b"raw_parts");

        let (ptr, len, cap) = buf.into_raw_parts();
        assert!(!ptr.is_null());
        assert_eq!(len, 9);
        assert!(cap >= 9);

        let reconstructed = unsafe { GcByteBuffer::from_raw_parts(ptr, len, cap) };
        assert_eq!(&reconstructed[..], b"raw_parts");
    }

    #[test]
    fn gc_byte_buffer_leak_check() {
        let initial_allocs = ALLOC_COUNT.load(Ordering::SeqCst);
        let initial_frees = FREE_COUNT.load(Ordering::SeqCst);

        {
            let mut buf = GcByteBuffer::new();
            for i in 0..100 {
                buf.push(i as u8);
            }
            assert_eq!(buf.len(), 100);
        }

        let final_allocs = ALLOC_COUNT.load(Ordering::SeqCst);
        let final_frees = FREE_COUNT.load(Ordering::SeqCst);

        let alloc_diff = final_allocs - initial_allocs;
        let free_diff = final_frees - initial_frees;

        assert!(alloc_diff > 0);
        assert_eq!(alloc_diff, free_diff, "Alloc count and free count must match (no memory leaks)");
    }
}
