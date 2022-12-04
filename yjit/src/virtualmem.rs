//! Memory management stuff for YJIT's code storage. Deals with virtual memory.
// I'm aware that there is an experiment in Rust Nightly right now for to see if banning
// usize->pointer casts is viable. It seems like a lot of work for us to participate for not much
// benefit.

use std::ptr::NonNull;

use crate::{utils::IntoUsize, backend::ir::Target};

#[cfg(not(test))]
pub type VirtualMem = VirtualMemory<sys::SystemAllocator>;

#[cfg(test)]
pub type VirtualMem = VirtualMemory<tests::TestingAllocator>;

/// Memory for generated executable machine code. When not testing, we reserve address space for
/// the entire region upfront and map physical memory into the reserved address space as needed. On
/// Linux, this is basically done using an `mmap` with `PROT_NONE` upfront and gradually using
/// `mprotect` with `PROT_READ|PROT_WRITE` as needed. The WIN32 equivalent seems to be
/// `VirtualAlloc` with `MEM_RESERVE` then later with `MEM_COMMIT`.
///
/// This handles ["W^X"](https://en.wikipedia.org/wiki/W%5EX) semi-automatically. Writes
/// are always accepted and once writes are done a call to [Self::mark_all_executable] makes
/// the code in the region executable.
pub struct VirtualMemory<A: Allocator> {
    /// Location of the virtual memory region.
    region_start: NonNull<u8>,

    /// Size of the region in bytes.
    region_size_bytes: usize,

    /// Number of bytes per "page", memory protection permission can only be controlled at this
    /// granularity.
    page_size_bytes: usize,

    /// Number of bytes that have we have allocated physical memory for starting at
    /// [Self::region_start].
    mapped_region_bytes: usize,

    /// Keep track of the address of the last written to page.
    /// Used for changing protection to implement W^X.
    current_write_page: Option<usize>,

    /// Zero size member for making syscalls to get physical memory during normal operation.
    /// When testing this owns some memory.
    allocator: A,
}

/// Groups together the two syscalls to get get new physical memory and to change
/// memory protection. See [VirtualMemory] for details.
pub trait Allocator {
    #[must_use]
    fn mark_writable(&mut self, ptr: *const u8, size: u32) -> bool;

    fn mark_executable(&mut self, ptr: *const u8, size: u32);

    fn mark_unused(&mut self, ptr: *const u8, size: u32) -> bool;
}

/// Pointer into a [VirtualMemory].
/// We may later change this to wrap an u32.
/// Note: there is no NULL constant for CodePtr. You should use Option<CodePtr> instead.
#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Debug)]
#[repr(C, packed)]
pub struct CodePtr(NonNull<u8>);

impl CodePtr {
    pub fn as_side_exit(self) -> Target {
        Target::SideExitPtr(self)
    }
}

/// Errors that can happen when writing to [VirtualMemory]
#[derive(Debug, PartialEq)]
pub enum WriteError {
    OutOfBounds,
    FailedPageMapping,
}

use WriteError::*;

impl<A: Allocator> VirtualMemory<A> {
    /// Bring a part of the address space under management.
    pub fn new(allocator: A, page_size: u32, virt_region_start: NonNull<u8>, size_bytes: usize) -> Self {
        assert_ne!(0, page_size);
        let page_size_bytes = page_size.as_usize();

        Self {
            region_start: virt_region_start,
            region_size_bytes: size_bytes,
            page_size_bytes,
            mapped_region_bytes: 0,
            current_write_page: None,
            allocator,
        }
    }

    /// Return the start of the region as a raw pointer. Note that it could be a dangling
    /// pointer so be careful dereferencing it.
    pub fn start_ptr(&self) -> CodePtr {
        CodePtr(self.region_start)
    }

    pub fn end_ptr(&self) -> CodePtr {
        CodePtr(NonNull::new(self.region_start.as_ptr().wrapping_add(self.mapped_region_bytes)).unwrap())
    }

    /// Size of the region in bytes that we have allocated physical memory for.
    pub fn mapped_region_size(&self) -> usize {
        self.mapped_region_bytes
    }

    /// Size of the region in bytes where writes could be attempted.
    pub fn virtual_region_size(&self) -> usize {
        self.region_size_bytes
    }

    /// Write a single byte. The first write to a page makes it readable.
    pub fn write_byte(&mut self, write_ptr: CodePtr, byte: u8) -> Result<(), WriteError> {
        let page_size = self.page_size_bytes;
        let raw: *mut u8 = write_ptr.raw_ptr() as *mut u8;
        let page_addr = (raw as usize / page_size) * page_size;

        if self.current_write_page == Some(page_addr) {
            // Writing within the last written to page, nothing to do
        } else {
            // Switching to a different and potentially new page
            let start = self.region_start.as_ptr();
            let mapped_region_end = start.wrapping_add(self.mapped_region_bytes);
            let whole_region_end = start.wrapping_add(self.region_size_bytes);
            let alloc = &mut self.allocator;

            assert!((start..=whole_region_end).contains(&mapped_region_end));

            if (start..mapped_region_end).contains(&raw) {
                // Writing to a previously written to page.
                // Need to make page writable, but no need to fill.
                let page_size: u32 = page_size.try_into().unwrap();
                if !alloc.mark_writable(page_addr as *const _, page_size) {
                    return Err(FailedPageMapping);
                }

                self.current_write_page = Some(page_addr);
            } else if (start..whole_region_end).contains(&raw) {
                // Writing to a brand new page
                let mapped_region_end_addr = mapped_region_end as usize;
                let alloc_size = page_addr - mapped_region_end_addr + page_size;

                assert_eq!(0, alloc_size % page_size, "allocation size should be page aligned");
                assert_eq!(0, mapped_region_end_addr % page_size, "pointer should be page aligned");

                if alloc_size > page_size {
                    // This is unusual for the current setup, so keep track of it.
                    crate::stats::incr_counter!(exec_mem_non_bump_alloc);
                }

                // Allocate new chunk
                let alloc_size_u32: u32 = alloc_size.try_into().unwrap();
                unsafe {
                    if !alloc.mark_writable(mapped_region_end.cast(), alloc_size_u32) {
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
                self.mapped_region_bytes = self.mapped_region_bytes + alloc_size;

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
        self.allocator.mark_executable(region_start.as_ptr(), mapped_region_bytes);
    }

    /// Free a range of bytes. start_ptr must be memory page-aligned.
    pub fn free_bytes(&mut self, start_ptr: CodePtr, size: u32) {
        assert_eq!(start_ptr.into_usize() % self.page_size_bytes, 0);
        self.allocator.mark_unused(start_ptr.0.as_ptr(), size);
    }
}

impl CodePtr {
    /// Note that the raw pointer might be dangling if there hasn't
    /// been any writes to it through the [VirtualMemory] yet.
    pub fn raw_ptr(self) -> *const u8 {
        let CodePtr(ptr) = self;
        return ptr.as_ptr();
    }

    /// Advance the CodePtr. Can return a dangling pointer.
    pub fn add_bytes(self, bytes: usize) -> Self {
        let CodePtr(raw) = self;
        CodePtr(NonNull::new(raw.as_ptr().wrapping_add(bytes)).unwrap())
    }

    pub fn into_i64(self) -> i64 {
        let CodePtr(ptr) = self;
        ptr.as_ptr() as i64
    }

    #[cfg(target_arch = "aarch64")]
    pub fn into_u64(self) -> u64 {
        let CodePtr(ptr) = self;
        ptr.as_ptr() as u64
    }

    pub fn into_usize(self) -> usize {
        let CodePtr(ptr) = self;
        ptr.as_ptr() as usize
    }
}

impl From<*mut u8> for CodePtr {
    fn from(value: *mut u8) -> Self {
        assert!(value as usize != 0);
        return CodePtr(NonNull::new(value).unwrap());
    }
}

/// Requires linking with CRuby to work
#[cfg(not(test))]
mod sys {
    use crate::cruby::*;

    /// Zero size! This just groups together syscalls that require linking with CRuby.
    pub struct SystemAllocator;

    type VoidPtr = *mut std::os::raw::c_void;

    impl super::Allocator for SystemAllocator {
        fn mark_writable(&mut self, ptr: *const u8, size: u32) -> bool {
            unsafe { rb_yjit_mark_writable(ptr as VoidPtr, size) }
        }

        fn mark_executable(&mut self, ptr: *const u8, size: u32) {
            unsafe { rb_yjit_mark_executable(ptr as VoidPtr, size) }
        }

        fn mark_unused(&mut self, ptr: *const u8, size: u32) -> bool {
            unsafe { rb_yjit_mark_unused(ptr as VoidPtr, size) }
        }
    }
}

#[cfg(not(test))]
pub(crate) use sys::*;


#[cfg(test)]
pub mod tests {
    use crate::utils::IntoUsize;
    use super::*;

    // Track allocation requests and owns some fixed size backing memory for requests.
    // While testing we don't execute generated code.
    pub struct TestingAllocator {
        requests: Vec<AllocRequest>,
        memory: Vec<u8>,
    }

    #[derive(Debug)]
    enum AllocRequest {
        MarkWritable{ start_idx: usize, length: usize },
        MarkExecutable{ start_idx: usize, length: usize },
        MarkUnused,
    }
    use AllocRequest::*;

    impl TestingAllocator {
        pub fn new(mem_size: usize) -> Self {
            Self { requests: Vec::default(), memory: vec![0; mem_size] }
        }

        pub fn mem_start(&self) -> *const u8 {
            self.memory.as_ptr()
        }

        // Verify that write_byte() bounds checks. Return `ptr` as an index.
        fn bounds_check_request(&self, ptr: *const u8, size: u32) -> usize {
            let mem_start = self.memory.as_ptr() as usize;
            let index = ptr as usize - mem_start;

            assert!(index < self.memory.len());
            assert!(index + size.as_usize() <= self.memory.len());

            index
        }
    }

    // Bounds check and then record the request
    impl super::Allocator for TestingAllocator {
        fn mark_writable(&mut self, ptr: *const u8, length: u32) -> bool {
            let index = self.bounds_check_request(ptr, length);
            self.requests.push(MarkWritable { start_idx: index, length: length.as_usize() });

            true
        }

        fn mark_executable(&mut self, ptr: *const u8, length: u32) {
            let index = self.bounds_check_request(ptr, length);
            self.requests.push(MarkExecutable { start_idx: index, length: length.as_usize() });

            // We don't try to execute generated code in cfg(test)
            // so no need to actually request executable memory.
        }

        fn mark_unused(&mut self, ptr: *const u8, length: u32) -> bool {
            self.bounds_check_request(ptr, length);
            self.requests.push(MarkUnused);

            true
        }
    }

    // Fictional architecture where each page is 4 bytes long
    const PAGE_SIZE: usize = 4;
    fn new_dummy_virt_mem() -> VirtualMemory<TestingAllocator> {
        let mem_size = PAGE_SIZE * 10;
        let alloc = TestingAllocator::new(mem_size);
        let mem_start: *const u8 = alloc.mem_start();

        VirtualMemory::new(
            alloc,
            PAGE_SIZE.try_into().unwrap(),
            NonNull::new(mem_start as *mut u8).unwrap(),
            mem_size,
        )
    }

    #[test]
    #[cfg(target_arch = "x86_64")]
    fn new_memory_is_initialized() {
        let mut virt = new_dummy_virt_mem();

        virt.write_byte(virt.start_ptr(), 1).unwrap();
        assert!(
            virt.allocator.memory[..PAGE_SIZE].iter().all(|&byte| byte != 0),
            "Entire page should be initialized",
        );

        // Skip a few page
        let three_pages = 3 * PAGE_SIZE;
        virt.write_byte(virt.start_ptr().add_bytes(three_pages), 1).unwrap();
        assert!(
            virt.allocator.memory[..three_pages].iter().all(|&byte| byte != 0),
            "Gaps between write requests should be filled",
        );
    }

    #[test]
    fn no_redundant_syscalls_when_writing_to_the_same_page() {
        let mut virt = new_dummy_virt_mem();

        virt.write_byte(virt.start_ptr(), 1).unwrap();
        virt.write_byte(virt.start_ptr(), 0).unwrap();

        assert!(
            matches!(
                virt.allocator.requests[..],
                [MarkWritable { start_idx: 0, length: PAGE_SIZE }],
            )
        );
    }

    #[test]
    fn bounds_checking() {
        use super::WriteError::*;
        let mut virt = new_dummy_virt_mem();

        let one_past_end = virt.start_ptr().add_bytes(virt.virtual_region_size());
        assert_eq!(Err(OutOfBounds), virt.write_byte(one_past_end, 0));

        let end_of_addr_space = CodePtr(NonNull::new(usize::MAX as _).unwrap());
        assert_eq!(Err(OutOfBounds), virt.write_byte(end_of_addr_space, 0));
    }

    #[test]
    fn only_written_to_regions_become_executable() {
        // ... so we catch attempts to read/write/execute never-written-to regions
        const THREE_PAGES: usize = PAGE_SIZE * 3;
        let mut virt = new_dummy_virt_mem();
        let page_two_start = virt.start_ptr().add_bytes(PAGE_SIZE * 2);
        virt.write_byte(page_two_start, 1).unwrap();
        virt.mark_all_executable();

        assert!(virt.virtual_region_size() > THREE_PAGES);
        assert!(
            matches!(
                virt.allocator.requests[..],
                [
                    MarkWritable { start_idx: 0, length: THREE_PAGES },
                    MarkExecutable { start_idx: 0, length: THREE_PAGES },
                ]
            ),
        );
    }
}
