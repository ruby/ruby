//! Custom GlobalAlloc implementation backing standard Rust collections with Ruby GC.
//!
//! Maps Rust memory allocations (`alloc`, `realloc`, `dealloc`) to Ruby's
//! memory management functions (`ruby_xmalloc`, `ruby_xrealloc`, `ruby_xfree`).

use core::alloc::{GlobalAlloc, Layout};
use core::ffi::c_void;
use core::ptr;

#[cfg(not(test))]
use crate::ffi::api::raising::{ruby_xmalloc, ruby_xrealloc};
#[cfg(not(test))]
use crate::ffi::api::ruby_xfree;

/// Maximum natural alignment guaranteed by standard malloc/ruby_xmalloc (16 bytes).
const MAX_NATURAL_ALIGN: usize = 16;

#[cfg(test)]
unsafe fn raw_malloc(size: usize) -> *mut c_void {
    unsafe extern "C" {
        fn malloc(size: usize) -> *mut c_void;
    }
    unsafe { malloc(size) }
}

#[cfg(test)]
unsafe fn raw_realloc(ptr: *mut c_void, new_size: usize) -> *mut c_void {
    unsafe extern "C" {
        fn realloc(ptr: *mut c_void, size: usize) -> *mut c_void;
    }
    unsafe { realloc(ptr, new_size) }
}

#[cfg(test)]
unsafe fn raw_free(ptr: *mut c_void) {
    unsafe extern "C" {
        fn free(ptr: *mut c_void);
    }
    unsafe { free(ptr) }
}

#[cfg(not(test))]
unsafe fn raw_malloc(size: usize) -> *mut c_void {
    unsafe { ruby_xmalloc(size) }
}

#[cfg(not(test))]
unsafe fn raw_realloc(ptr: *mut c_void, new_size: usize) -> *mut c_void {
    unsafe { ruby_xrealloc(ptr, new_size) }
}

#[cfg(not(test))]
unsafe fn raw_free(ptr: *mut c_void) {
    unsafe {
        ruby_xfree(ptr);
    }
}

/// Custom global allocator for Ruby GC integration.
pub struct RubyGlobalAlloc;

unsafe impl GlobalAlloc for RubyGlobalAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let size = layout.size();
        let align = layout.align();

        if size == 0 {
            return align as *mut u8;
        }

        if align <= MAX_NATURAL_ALIGN {
            let p = unsafe { raw_malloc(size) };
            p as *mut u8
        } else {
            // Over-aligned allocation: pad size and store original pointer header
            let header_size = core::mem::size_of::<*mut u8>();
            let padded_size = match size.checked_add(align + header_size) {
                Some(s) => s,
                None => return ptr::null_mut(),
            };

            let raw = unsafe { raw_malloc(padded_size) } as *mut u8;
            if raw.is_null() {
                return ptr::null_mut();
            }

            let raw_addr = raw as usize;
            let aligned_addr = (raw_addr + header_size + align - 1) & !(align - 1);
            let header_ptr = (aligned_addr - header_size) as *mut *mut u8;
            unsafe {
                ptr::write_unaligned(header_ptr, raw);
            }
            aligned_addr as *mut u8
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if ptr.is_null() || layout.size() == 0 {
            return;
        }

        let align = layout.align();
        if align <= MAX_NATURAL_ALIGN {
            unsafe { raw_free(ptr as *mut c_void) };
        } else {
            let header_size = core::mem::size_of::<*mut u8>();
            let header_ptr = (ptr as usize - header_size) as *const *mut u8;
            let raw = unsafe { ptr::read_unaligned(header_ptr) };
            unsafe { raw_free(raw as *mut c_void) };
        }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let align = layout.align();

        if ptr.is_null() || layout.size() == 0 {
            if new_size == 0 {
                return align as *mut u8;
            }
            let new_layout = match Layout::from_size_align(new_size, align) {
                Ok(l) => l,
                Err(_) => return ptr::null_mut(),
            };
            return unsafe { self.alloc(new_layout) };
        }

        if new_size == 0 {
            unsafe { self.dealloc(ptr, layout) };
            return align as *mut u8;
        }

        if align <= MAX_NATURAL_ALIGN {
            let p = unsafe { raw_realloc(ptr as *mut c_void, new_size) };
            p as *mut u8
        } else {
            // For over-aligned memory, allocate new layout and copy existing bytes
            let new_layout = match Layout::from_size_align(new_size, align) {
                Ok(l) => l,
                Err(_) => return ptr::null_mut(),
            };
            let new_ptr = unsafe { self.alloc(new_layout) };
            if new_ptr.is_null() {
                return ptr::null_mut();
            }
            let copy_size = core::cmp::min(layout.size(), new_size);
            unsafe {
                ptr::copy_nonoverlapping(ptr, new_ptr, copy_size);
                self.dealloc(ptr, layout);
            }
            new_ptr
        }
    }
}

#[global_allocator]
static ALLOCATOR: RubyGlobalAlloc = RubyGlobalAlloc;

#[cfg(test)]
mod tests {
    use std_alloc::boxed::Box;
    use std_alloc::string::String;
    use std_alloc::vec::Vec;

    #[test]
    fn vec_operations() {
        let mut v: Vec<i32> = Vec::new();
        assert_eq!(v.len(), 0);
        for i in 0..100 {
            v.push(i);
        }
        assert_eq!(v.len(), 100);
        let sum: i32 = v.iter().sum();
        assert_eq!(sum, 4950);
        assert_eq!(v.pop(), Some(99));
        assert_eq!(v.len(), 99);
    }

    #[test]
    fn box_operations() {
        let b = Box::new(123456789u64);
        assert_eq!(*b, 123456789u64);
    }

    #[test]
    fn string_operations() {
        let mut s = String::from("Hello, ");
        s.push_str("Ruby on Rust!");
        assert_eq!(s.as_str(), "Hello, Ruby on Rust!");
    }

    #[test]
    fn zero_sized_allocations() {
        let mut v: Vec<()> = Vec::new();
        v.push(());
        v.push(());
        assert_eq!(v.len(), 2);
        let b = Box::new(());
        assert_eq!(*b, ());
    }

    #[test]
    fn zero_sized_realloc() {
        use super::RubyGlobalAlloc;
        use core::alloc::GlobalAlloc;
        use core::alloc::Layout;

        let alloc = RubyGlobalAlloc;
        let layout0 = Layout::from_size_align(0, 8).unwrap();
        let ptr0 = unsafe { alloc.alloc(layout0) };
        assert_eq!(ptr0 as usize, 8);

        // Realloc from size 0 to size 16
        let ptr16 = unsafe { alloc.realloc(ptr0, layout0, 16) };
        assert!(!ptr16.is_null());
        assert_ne!(ptr16 as usize, 8);

        // Realloc back from size 16 to size 0
        let layout16 = Layout::from_size_align(16, 8).unwrap();
        let ptr_zero = unsafe { alloc.realloc(ptr16, layout16, 0) };
        assert_eq!(ptr_zero as usize, 8);
    }

    #[repr(align(64))]
    struct OverAligned {
        data: [u64; 8],
    }

    #[test]
    fn over_aligned_allocations() {
        let b = Box::new(OverAligned { data: [42; 8] });
        let addr = &*b as *const OverAligned as usize;
        assert_eq!(addr % 64, 0);
        assert_eq!(b.data[0], 42);
    }
}
