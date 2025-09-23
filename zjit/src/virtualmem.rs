//! Memory management stuff for ZJIT's code storage. Deals with virtual memory.
// I'm aware that there is an experiment in Rust Nightly right now for to see if banning
// usize->pointer casts is viable. It seems like a lot of work for us to participate for not much
// benefit.

use std::ptr::NonNull;
use crate::cruby::*;
use crate::stats::zjit_alloc_size;

/// Memory for generated executable machine code. When not testing, we reserve address space for
/// the entire region upfront and map physical memory into the reserved address space as needed. On
/// Linux, this is basically done using an `mmap` with `PROT_NONE` upfront and gradually using
/// `mprotect` with `PROT_READ|PROT_WRITE` as needed. The WIN32 equivalent seems to be
/// `VirtualAlloc` with `MEM_RESERVE` then later with `MEM_COMMIT`.
///
/// This handles ["W^X"](https://en.wikipedia.org/wiki/W%5EX) semi-automatically. Writes
/// are always accepted and once writes are done a call to [Self::mark_all_executable] makes
/// the code in the region executable.
pub struct VirtualMem {
    /// Location of the virtual memory region.
    region_start: NonNull<u8>,

    /// Size of this virtual memory region in bytes.
    region_size_bytes: usize,

    /// mapped_region_bytes + zjit_alloc_size may not increase beyond this limit.
    memory_limit_bytes: Option<usize>,

    /// Number of bytes per "page", memory protection permission can only be controlled at this
    /// granularity.
    page_size_bytes: usize,

    /// Number of bytes that have we have allocated physical memory for starting at
    /// [Self::region_start].
    mapped_region_bytes: usize,

    /// Keep track of the address of the last written to page.
    /// Used for changing protection to implement W^X.
    current_write_page: Option<usize>,
}

/// Groups together the two syscalls to get get new physical memory and to change
/// memory protection. See [VirtualMemory] for details.
pub trait Allocator {
    #[must_use]
    fn mark_writable(&mut self, ptr: *const u8, size: u32) -> bool;

    fn mark_executable(&mut self, ptr: *const u8, size: u32);

    fn mark_unused(&mut self, ptr: *const u8, size: u32) -> bool;
}

/// Pointer into a [VirtualMemory] represented as an offset from the base.
/// Note: there is no NULL constant for [CodePtr]. You should use `Option<CodePtr>` instead.
#[derive(Copy, Clone, PartialEq, Eq, Hash, PartialOrd, Debug)]
#[repr(C, packed)]
pub struct CodePtr(u32);

impl CodePtr {
    /// Advance the CodePtr. Can return a dangling pointer.
    pub fn add_bytes(self, bytes: usize) -> Self {
        let CodePtr(raw) = self;
        let bytes: u32 = bytes.try_into().unwrap();
        CodePtr(raw + bytes)
    }

    /// Subtract bytes from the CodePtr
    pub fn sub_bytes(self, bytes: usize) -> Self {
        let CodePtr(raw) = self;
        let bytes: u32 = bytes.try_into().unwrap();
        CodePtr(raw.saturating_sub(bytes))
    }

    /// Note that the raw pointer might be dangling if there hasn't
    /// been any writes to it through the [VirtualMemory] yet.
    pub fn raw_ptr(self, base: &impl CodePtrBase) -> *const u8 {
        let CodePtr(offset) = self;
        base.base_ptr().as_ptr().wrapping_add(offset as usize)
    }

    /// Get the address of the code pointer.
    pub fn raw_addr(self, base: &impl CodePtrBase) -> usize {
        self.raw_ptr(base) as usize
    }

    /// Get the offset component for the code pointer. Useful finding the distance between two
    /// code pointers that share the same [VirtualMem].
    pub fn as_offset(self) -> i64 {
        let CodePtr(offset) = self;
        offset.into()
    }
}

/// Errors that can happen when writing to [VirtualMemory]
#[derive(Debug, PartialEq)]
pub enum WriteError {
    OutOfBounds,
    FailedPageMapping,
}

use WriteError::*;

impl VirtualMem {
    /// Bring a part of the address space under management.
    pub fn new(
        page_size: u32,
        virt_region_start: NonNull<u8>,
        region_size_bytes: usize,
        memory_limit_bytes: Option<usize>,
    ) -> Self {
        assert_ne!(0, page_size);
        let page_size_bytes = page_size as usize;

        Self {
            region_start: virt_region_start,
            region_size_bytes,
            memory_limit_bytes,
            page_size_bytes,
            mapped_region_bytes: 0,
            current_write_page: None,
        }
    }

    /// Allocate a VirtualMem insntace with a requested size
    pub fn alloc(exec_mem_bytes: usize, mem_bytes: Option<usize>) -> Self {
        let virt_block: *mut u8 = unsafe { rb_jit_reserve_addr_space(exec_mem_bytes as u32) };

        // Memory protection syscalls need page-aligned addresses, so check it here. Assuming
        // `virt_block` is page-aligned, `second_half` should be page-aligned as long as the
        // page size in bytes is a power of two 2¹⁹ or smaller. This is because the user
        // requested size is half of mem_option × 2²⁰ as it's in MiB.
        //
        // Basically, we don't support x86-64 2MiB and 1GiB pages. ARMv8 can do up to 64KiB
        // (2¹⁶ bytes) pages, which should be fine. 4KiB pages seem to be the most popular though.
        let page_size = unsafe { rb_jit_get_page_size() };
        assert_eq!(
            virt_block as usize % page_size as usize, 0,
            "Start of virtual address block should be page-aligned",
        );

        Self::new(page_size, NonNull::new(virt_block).unwrap(), exec_mem_bytes, mem_bytes)
    }

    /// Return the start of the region as a raw pointer. Note that it could be a dangling
    /// pointer so be careful dereferencing it.
    pub fn start_ptr(&self) -> CodePtr {
        CodePtr(0)
    }

    pub fn mapped_end_ptr(&self) -> CodePtr {
        self.start_ptr().add_bytes(self.mapped_region_bytes)
    }

    pub fn virtual_end_ptr(&self) -> CodePtr {
        self.start_ptr().add_bytes(self.region_size_bytes)
    }

    /// Size of the region in bytes that we have allocated physical memory for.
    pub fn mapped_region_size(&self) -> usize {
        self.mapped_region_bytes
    }

    /// Size of the region in bytes where writes could be attempted.
    pub fn virtual_region_size(&self) -> usize {
        self.region_size_bytes
    }

    /// The granularity at which we can control memory permission.
    /// On Linux, this is the page size that mmap(2) talks about.
    pub fn system_page_size(&self) -> usize {
        self.page_size_bytes
    }

    /// Write a single byte. The first write to a page makes it readable.
    pub fn write_byte(&mut self, write_ptr: CodePtr, byte: u8) -> Result<(), WriteError> {
        let page_size = self.page_size_bytes;
        let raw: *mut u8 = write_ptr.raw_ptr(self) as *mut u8;
        let page_addr = (raw as usize / page_size) * page_size;

        if self.current_write_page == Some(page_addr) {
            // Writing within the last written to page, nothing to do
        } else {
            // Switching to a different and potentially new page
            let start = self.region_start.as_ptr();
            let mapped_region_end = start.wrapping_add(self.mapped_region_bytes);
            let whole_region_end = start.wrapping_add(self.region_size_bytes);

            // Ignore zjit_alloc_size() if self.memory_limit_bytes is None for testing
            let mut required_region_bytes = page_addr + page_size - start as usize;
            if self.memory_limit_bytes.is_some() {
                required_region_bytes += zjit_alloc_size();
            }

            assert!((start..=whole_region_end).contains(&mapped_region_end));

            if (start..mapped_region_end).contains(&raw) {
                // Writing to a previously written to page.
                // Need to make page writable, but no need to fill.
                let page_size: u32 = page_size.try_into().unwrap();
                if !self.mark_writable(page_addr as *const _, page_size) {
                    return Err(FailedPageMapping);
                }

                self.current_write_page = Some(page_addr);
            } else if (start..whole_region_end).contains(&raw) &&
                    required_region_bytes < self.memory_limit_bytes.unwrap_or(self.region_size_bytes) {
                // Writing to a brand new page
                let mapped_region_end_addr = mapped_region_end as usize;
                let alloc_size = page_addr - mapped_region_end_addr + page_size;

                assert_eq!(0, alloc_size % page_size, "allocation size should be page aligned");
                assert_eq!(0, mapped_region_end_addr % page_size, "pointer should be page aligned");

                if alloc_size > page_size {
                    // This is unusual for the current setup, so keep track of it.
                    //crate::stats::incr_counter!(exec_mem_non_bump_alloc); // TODO
                }

                // Allocate new chunk
                let alloc_size_u32: u32 = alloc_size.try_into().unwrap();
                unsafe {
                    if !self.mark_writable(mapped_region_end.cast(), alloc_size_u32) {
                        return Err(FailedPageMapping);
                    }
                    if cfg!(target_arch = "x86_64") {
                        // Fill new memory with PUSH DS (0x1E) so that executing uninitialized memory
                        // will fault with #UD in 64-bit mode. On Linux it becomes SIGILL and use the
                        // usual Ruby crash reporter.
                        std::slice::from_raw_parts_mut(mapped_region_end, alloc_size).fill(0x1E);
                    } else if cfg!(target_arch = "aarch64") {
                        // In aarch64, all zeros encodes UDF, so it's already what we want.
                    } else {
                        unreachable!("unknown arch");
                    }
                }
                self.mapped_region_bytes += alloc_size;

                self.current_write_page = Some(page_addr);
            } else {
                return Err(OutOfBounds);
            }
        }

        // We have permission to write if we get here
        unsafe { raw.write(byte) };

        Ok(())
    }

    /// Make all the code in the region executable. Call this at the end of a write session.
    /// See [Self] for usual usage flow.
    pub fn mark_all_executable(&mut self) {
        self.current_write_page = None;

        let region_start = self.region_start;
        let mapped_region_bytes: u32 = self.mapped_region_bytes.try_into().unwrap();

        // Make mapped region executable
        self.mark_executable(region_start.as_ptr(), mapped_region_bytes);
    }

    /// Free a range of bytes. start_ptr must be memory page-aligned.
    pub fn free_bytes(&mut self, start_ptr: CodePtr, size: u32) {
        assert_eq!(start_ptr.raw_ptr(self) as usize % self.page_size_bytes, 0);

        // Bounds check the request. We should only free memory we manage.
        let mapped_region = self.start_ptr().raw_ptr(self)..self.mapped_end_ptr().raw_ptr(self);
        let virtual_region = self.start_ptr().raw_ptr(self)..self.virtual_end_ptr().raw_ptr(self);
        let last_byte_to_free = start_ptr.add_bytes(size.saturating_sub(1) as usize).raw_ptr(self);
        assert!(mapped_region.contains(&start_ptr.raw_ptr(self)));
        // On platforms where code page size != memory page size (e.g. Linux), we often need
        // to free code pages that contain unmapped memory pages. When it happens on the last
        // code page, it's more appropriate to check the last byte against the virtual region.
        assert!(virtual_region.contains(&last_byte_to_free));

        self.mark_unused(start_ptr.raw_ptr(self), size);
    }

    fn mark_writable(&mut self, ptr: *const u8, size: u32) -> bool {
        unsafe { rb_jit_mark_writable(ptr as VoidPtr, size) }
    }

    fn mark_executable(&mut self, ptr: *const u8, size: u32) {
        unsafe { rb_jit_mark_executable(ptr as VoidPtr, size) }
    }

    fn mark_unused(&mut self, ptr: *const u8, size: u32) -> bool {
        unsafe { rb_jit_mark_unused(ptr as VoidPtr, size) }
    }
}

type VoidPtr = *mut std::os::raw::c_void;

/// Something that could provide a base pointer to compute a raw pointer from a [CodePtr].
pub trait CodePtrBase {
    fn base_ptr(&self) -> NonNull<u8>;
}

impl CodePtrBase for VirtualMem {
    fn base_ptr(&self) -> NonNull<u8> {
        self.region_start
    }
}

/// Requires linking with CRuby to work
pub mod sys {
    use crate::cruby::*;

    /// Zero size! This just groups together syscalls that require linking with CRuby.
    pub struct SystemAllocator;

    type VoidPtr = *mut std::os::raw::c_void;

    impl super::Allocator for SystemAllocator {
        fn mark_writable(&mut self, ptr: *const u8, size: u32) -> bool {
            unsafe { rb_jit_mark_writable(ptr as VoidPtr, size) }
        }

        fn mark_executable(&mut self, ptr: *const u8, size: u32) {
            unsafe { rb_jit_mark_executable(ptr as VoidPtr, size) }
        }

        fn mark_unused(&mut self, ptr: *const u8, size: u32) -> bool {
            unsafe { rb_jit_mark_unused(ptr as VoidPtr, size) }
        }
    }
}
