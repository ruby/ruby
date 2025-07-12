use std::cell::RefCell;
use std::fmt;
use std::mem;
use std::rc::Rc;
use std::collections::BTreeMap;

use crate::core::IseqPayload;
use crate::core::for_each_off_stack_iseq_payload;
use crate::core::for_each_on_stack_iseq_payload;
use crate::invariants::rb_yjit_tracing_invalidate_all;
use crate::stats::incr_counter;
use crate::virtualmem::WriteError;
use crate::codegen::CodegenGlobals;
use crate::virtualmem::{VirtualMem, CodePtr};

// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
pub mod x86_64;

pub mod arm64;

//
// TODO: need a field_size_of macro, to compute the size of a struct field in bytes
//

/// Reference to an ASM label
#[derive(Clone)]
pub struct LabelRef {
    // Position in the code block where the label reference exists
    pos: usize,

    // Label which this refers to
    label_idx: usize,

    /// The number of bytes that this label reference takes up in the memory.
    /// It's necessary to know this ahead of time so that when we come back to
    /// patch it it takes the same amount of space.
    num_bytes: usize,

    /// The object that knows how to encode the branch instruction.
    encode: fn(&mut CodeBlock, i64, i64)
}

/// Block of memory into which instructions can be assembled
pub struct CodeBlock {
    // Memory for storing the encoded instructions
    mem_block: Rc<RefCell<VirtualMem>>,

    // Size of a code page in bytes. Each code page is split into an inlined and an outlined portion.
    // Code GC collects code memory at this granularity.
    // Must be a multiple of the OS page size.
    page_size: usize,

    // Memory block size
    mem_size: usize,

    // Current writing position
    write_pos: usize,

    // The index of the last page with written bytes
    last_page_idx: usize,

    // Total number of bytes written to past pages
    past_page_bytes: usize,

    // Size reserved for writing a jump to the next page
    page_end_reserve: usize,

    // Table of registered label addresses
    label_addrs: Vec<usize>,

    // Table of registered label names
    label_names: Vec<String>,

    // References to labels
    label_refs: Vec<LabelRef>,

    // A switch for keeping comments. They take up memory.
    keep_comments: bool,

    // Comments for assembly instructions, if that feature is enabled
    asm_comments: BTreeMap<usize, Vec<String>>,

    // True for OutlinedCb
    pub outlined: bool,

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,

    // Keeps track of what pages we can write to after code gc.
    // `None` means all pages are free.
    freed_pages: Rc<Option<Vec<usize>>>,
}

/// Set of CodeBlock label states. Used for recovering the previous state.
pub struct LabelState {
    label_addrs: Vec<usize>,
    label_names: Vec<String>,
    label_refs: Vec<LabelRef>,
}

impl CodeBlock {
    /// Works for common AArch64 systems that have 16 KiB pages and
    /// common x86_64 systems that use 4 KiB pages.
    const PREFERRED_CODE_PAGE_SIZE: usize = 16 * 1024;

    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>, outlined: bool, freed_pages: Rc<Option<Vec<usize>>>, keep_comments: bool) -> Self {
        // Pick the code page size
        let system_page_size = mem_block.borrow().system_page_size();
        let page_size = if 0 == Self::PREFERRED_CODE_PAGE_SIZE % system_page_size {
            Self::PREFERRED_CODE_PAGE_SIZE
        } else {
            system_page_size
        };

        let mem_size = mem_block.borrow().virtual_region_size();
        let mut cb = Self {
            mem_block,
            mem_size,
            page_size,
            write_pos: 0,
            last_page_idx: 0,
            past_page_bytes: 0,
            page_end_reserve: 0,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            keep_comments,
            asm_comments: BTreeMap::new(),
            outlined,
            dropped_bytes: false,
            freed_pages,
        };
        cb.page_end_reserve = cb.jmp_ptr_bytes();
        cb.write_pos = cb.page_start();

        #[cfg(not(test))]
        assert_eq!(0, mem_size % page_size, "partially in-bounds code pages should be impossible");

        cb
    }

    /// Move the CodeBlock to the next page. If it's on the furthest page,
    /// move the other CodeBlock to the next page as well.
    #[must_use]
    pub fn next_page<F: Fn(&mut CodeBlock, CodePtr)>(&mut self, base_ptr: CodePtr, jmp_ptr: F) -> bool {
        let old_write_ptr = self.get_write_ptr();
        self.set_write_ptr(base_ptr);

        // Use the freed_pages list if code GC has been used. Otherwise use the next page.
        let next_page_idx = if let Some(freed_pages) = self.freed_pages.as_ref() {
            let current_page = self.write_pos / self.page_size;
            freed_pages.iter().find(|&&page| current_page < page).map(|&page| page)
        } else {
            Some(self.write_pos / self.page_size + 1)
        };

        // Move self to the next page
        if next_page_idx.is_none() || !self.set_page(next_page_idx.unwrap(), &jmp_ptr) {
            self.set_write_ptr(old_write_ptr); // rollback if there are no more pages
            return false;
        }

        // Move the other CodeBlock to the same page if it's on the furthest page
        if cfg!(not(test)) {
            self.other_cb().unwrap().set_page(next_page_idx.unwrap(), &jmp_ptr);
        }

        return !self.dropped_bytes;
    }

    /// Move the CodeBlock to page_idx only if it's not going backwards.
    fn set_page<F: Fn(&mut CodeBlock, CodePtr)>(&mut self, page_idx: usize, jmp_ptr: &F) -> bool {
        // Do not move the CodeBlock if page_idx points to an old position so that this
        // CodeBlock will not overwrite existing code.
        //
        // Let's say this is the current situation:
        //   cb: [page1, page2, page3 (write_pos)], ocb: [page1, page2, page3 (write_pos)]
        //
        // When cb needs to patch page1, this will be temporarily changed to:
        //   cb: [page1 (write_pos), page2, page3], ocb: [page1, page2, page3 (write_pos)]
        //
        // While patching page1, cb may need to jump to page2. What set_page currently does is:
        //   cb: [page1, page2 (write_pos), page3], ocb: [page1, page2, page3 (write_pos)]
        // instead of:
        //   cb: [page1, page2 (write_pos), page3], ocb: [page1, page2 (write_pos), page3]
        // because moving ocb's write_pos from page3 to the beginning of page2 will let ocb's
        // write_pos point to existing code in page2, which might let ocb overwrite it later.
        //
        // We could remember the last write_pos in page2 and let set_page use that position,
        // but you need to waste some space for keeping write_pos for every single page.
        // It doesn't seem necessary for performance either. So we're currently not doing it.
        let dst_pos = self.get_page_pos(page_idx);
        if self.write_pos < dst_pos {
            // Fail if next page is out of bounds
            if dst_pos >= self.mem_size {
                return false;
            }

            // Reset dropped_bytes
            self.dropped_bytes = false;

            // Generate jmp_ptr from src_pos to dst_pos
            let dst_ptr = self.get_ptr(dst_pos);
            self.without_page_end_reserve(|cb| {
                assert!(cb.has_capacity(cb.jmp_ptr_bytes()));
                cb.add_comment("jump to next page");
                jmp_ptr(cb, dst_ptr);
            });

            // Update past_page_bytes for code_size() if this is a new page
            if self.last_page_idx < page_idx {
                self.past_page_bytes += self.current_page_bytes();
            }

            // Start the next code from dst_pos
            self.write_pos = dst_pos;
            // Update the last_page_idx if page_idx points to the furthest page
            self.last_page_idx = usize::max(self.last_page_idx, page_idx);
        }
        !self.dropped_bytes
    }

    /// Free the memory pages of given code page indexes
    fn free_pages(&mut self, page_idxs: &Vec<usize>) {
        let mut page_idxs = page_idxs.clone();
        page_idxs.reverse(); // to loop with pop()

        // Group adjacent page indexes and free them in batches to reduce the # of syscalls.
        while let Some(page_idx) = page_idxs.pop() {
            // Group first adjacent page indexes
            let mut batch_idxs = vec![page_idx];
            while page_idxs.last() == Some(&(batch_idxs.last().unwrap() + 1)) {
                batch_idxs.push(page_idxs.pop().unwrap());
            }

            // Free the grouped pages at once
            let start_ptr = self.mem_block.borrow().start_ptr().add_bytes(page_idx * self.page_size);
            let batch_size = self.page_size * batch_idxs.len();
            self.mem_block.borrow_mut().free_bytes(start_ptr, batch_size as u32);
        }
    }

    pub fn page_size(&self) -> usize {
        self.page_size
    }

    pub fn mapped_region_size(&self) -> usize {
        self.mem_block.borrow().mapped_region_size()
    }

    /// Size of the region in bytes where writes could be attempted.
    #[cfg(target_arch = "aarch64")]
    pub fn virtual_region_size(&self) -> usize {
        self.mem_block.borrow().virtual_region_size()
    }

    /// Return the number of code pages that have been mapped by the VirtualMemory.
    pub fn num_mapped_pages(&self) -> usize {
        // CodeBlock's page size != VirtualMem's page size on Linux,
        // so mapped_region_size % self.page_size may not be 0
        ((self.mapped_region_size() - 1) / self.page_size) + 1
    }

    /// Return the number of code pages that have been reserved by the VirtualMemory.
    pub fn num_virtual_pages(&self) -> usize {
        let virtual_region_size = self.mem_block.borrow().virtual_region_size();
        // CodeBlock's page size != VirtualMem's page size on Linux,
        // so mapped_region_size % self.page_size may not be 0
        ((virtual_region_size - 1) / self.page_size) + 1
    }

    /// Return the number of code pages that have been freed and not used yet.
    pub fn num_freed_pages(&self) -> usize {
        (0..self.num_mapped_pages()).filter(|&page_idx| self.has_freed_page(page_idx)).count()
    }

    pub fn has_freed_page(&self, page_idx: usize) -> bool {
        self.freed_pages.as_ref().as_ref().map_or(false, |pages| pages.contains(&page_idx)) && // code GCed
            self.write_pos < page_idx * self.page_size // and not written yet
    }

    /// Convert a page index to the write_pos for the page start.
    fn get_page_pos(&self, page_idx: usize) -> usize {
        self.page_size * page_idx + self.page_start()
    }

    /// write_pos of the current page start
    pub fn page_start_pos(&self) -> usize {
        self.get_write_pos() / self.page_size * self.page_size + self.page_start()
    }

    /// Offset of each page where CodeBlock should start writing
    pub fn page_start(&self) -> usize {
        let mut start = if self.inline() {
            0
        } else {
            self.page_size / 2
        };
        if cfg!(debug_assertions) && !cfg!(test) {
            // Leave illegal instructions at the beginning of each page to assert
            // we're not accidentally crossing page boundaries.
            start += self.jmp_ptr_bytes();
        }
        start
    }

    /// Offset of each page where CodeBlock should stop writing (exclusive)
    pub fn page_end(&self) -> usize {
        let page_end = if self.inline() {
            self.page_size / 2
        } else {
            self.page_size
        };
        page_end - self.page_end_reserve // reserve space to jump to the next page
    }

    /// Call a given function with page_end_reserve = 0
    pub fn without_page_end_reserve<F: Fn(&mut Self)>(&mut self, block: F) {
        let old_page_end_reserve = self.page_end_reserve;
        self.page_end_reserve = 0;
        block(self);
        self.page_end_reserve = old_page_end_reserve;
    }

    /// Return the address ranges of a given address range that this CodeBlock can write.
    #[allow(dead_code)]
    pub fn writable_addrs(&self, start_ptr: CodePtr, end_ptr: CodePtr) -> Vec<(usize, usize)> {
        let region_start = self.get_ptr(0).raw_addr(self);
        let region_end = self.get_ptr(self.get_mem_size()).raw_addr(self);
        let mut start = start_ptr.raw_addr(self);
        let end = std::cmp::min(end_ptr.raw_addr(self), region_end);

        let freed_pages = self.freed_pages.as_ref().as_ref();
        let mut addrs = vec![];
        while start < end {
            let page_idx = start.saturating_sub(region_start) / self.page_size;
            let current_page = region_start + (page_idx * self.page_size);
            let page_end = std::cmp::min(end, current_page + self.page_end());
            // If code GC has been used, skip pages that are used by past on-stack code
            if freed_pages.map_or(true, |pages| pages.contains(&page_idx)) {
                addrs.push((start, page_end));
            }
            start = current_page + self.page_size + self.page_start();
        }
        addrs
    }

    /// Return the number of bytes written by this CodeBlock.
    pub fn code_size(&self) -> usize {
        self.current_page_bytes() + self.past_page_bytes
    }

    /// Return the number of bytes written to the current page.
    fn current_page_bytes(&self) -> usize {
        (self.write_pos % self.page_size).saturating_sub(self.page_start())
    }

    /// Check if this code block has sufficient remaining capacity
    pub fn has_capacity(&self, num_bytes: usize) -> bool {
        let page_offset = self.write_pos % self.page_size;
        let capacity = self.page_end().saturating_sub(page_offset);
        num_bytes <= capacity
    }

    /// Add an assembly comment if the feature is on.
    pub fn add_comment(&mut self, comment: &str) {
        if !self.keep_comments {
            return;
        }

        let cur_ptr = self.get_write_ptr().raw_addr(self);

        // If there's no current list of comments for this line number, add one.
        let this_line_comments = self.asm_comments.entry(cur_ptr).or_default();

        // Unless this comment is the same as the last one at this same line, add it.
        if this_line_comments.last().map(String::as_str) != Some(comment) {
            this_line_comments.push(comment.to_string());
        }
    }

    pub fn comments_at(&self, pos: usize) -> Option<&Vec<String>> {
        self.asm_comments.get(&pos)
    }

    pub fn remove_comments(&mut self, start_addr: CodePtr, end_addr: CodePtr) {
        if self.asm_comments.is_empty() {
            return;
        }
        for addr in start_addr.raw_addr(self)..end_addr.raw_addr(self) {
            self.asm_comments.remove(&addr);
        }
    }

    pub fn clear_comments(&mut self) {
        self.asm_comments.clear();
    }

    pub fn get_mem_size(&self) -> usize {
        self.mem_size
    }

    pub fn get_write_pos(&self) -> usize {
        self.write_pos
    }

    pub fn write_mem(&self, write_ptr: CodePtr, byte: u8) -> Result<(), WriteError> {
        self.mem_block.borrow_mut().write_byte(write_ptr, byte)
    }

    // Set the current write position
    pub fn set_pos(&mut self, pos: usize) {
        // No bounds check here since we can be out of bounds
        // when the code block fills up. We want to be able to
        // restore to the filled up state after patching something
        // in the middle.
        self.write_pos = pos;
    }

    // Set the current write position from a pointer
    pub fn set_write_ptr(&mut self, code_ptr: CodePtr) {
        let pos = code_ptr.as_offset() - self.mem_block.borrow().start_ptr().as_offset();
        self.set_pos(pos.try_into().unwrap());
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.mem_block.borrow().start_ptr().add_bytes(offset)
    }

    /// Convert an address range to memory page indexes against a num_pages()-sized array.
    pub fn addrs_to_pages(&self, start_addr: CodePtr, end_addr: CodePtr) -> impl Iterator<Item = usize> {
        let mem_start = self.mem_block.borrow().start_ptr().raw_addr(self);
        let mem_end = self.mem_block.borrow().mapped_end_ptr().raw_addr(self);
        assert!(mem_start <= start_addr.raw_addr(self));
        assert!(start_addr.raw_addr(self) <= end_addr.raw_addr(self));
        assert!(end_addr.raw_addr(self) <= mem_end);

        // Ignore empty code ranges
        if start_addr == end_addr {
            return (0..0).into_iter();
        }

        let start_page = (start_addr.raw_addr(self) - mem_start) / self.page_size;
        let end_page = (end_addr.raw_addr(self) - mem_start - 1) / self.page_size;
        (start_page..end_page + 1).into_iter()
    }

    /// Get a (possibly dangling) direct pointer to the current write position
    pub fn get_write_ptr(&self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, byte: u8) {
        let write_ptr = self.get_write_ptr();
        if self.has_capacity(1) && self.mem_block.borrow_mut().write_byte(write_ptr, byte).is_ok() {
            self.write_pos += 1;
        } else {
            self.dropped_bytes = true;
        }
    }

    /// Write multiple bytes starting from the current position.
    pub fn write_bytes(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.write_byte(*byte);
        }
    }

    /// Write an integer over the given number of bits at the current position.
    fn write_int(&mut self, val: u64, num_bits: u32) {
        assert!(num_bits > 0);
        assert!(num_bits % 8 == 0);

        // Switch on the number of bits
        match num_bits {
            8 => self.write_byte(val as u8),
            16 => self.write_bytes(&[(val & 0xff) as u8, ((val >> 8) & 0xff) as u8]),
            32 => self.write_bytes(&[
                (val & 0xff) as u8,
                ((val >> 8) & 0xff) as u8,
                ((val >> 16) & 0xff) as u8,
                ((val >> 24) & 0xff) as u8,
            ]),
            _ => {
                let mut cur = val;

                // Write out the bytes
                for _byte in 0..(num_bits / 8) {
                    self.write_byte((cur & 0xff) as u8);
                    cur >>= 8;
                }
            }
        }
    }

    /// Check if bytes have been dropped (unwritten because of insufficient space)
    pub fn has_dropped_bytes(&self) -> bool {
        self.dropped_bytes
    }

    /// To patch code that straddle pages correctly, we need to start with
    /// the dropped bytes flag unset so we can detect when to switch to a new page.
    pub fn set_dropped_bytes(&mut self, dropped_bytes: bool) {
        self.dropped_bytes = dropped_bytes;
    }

    /// Allocate a new label with a given name
    pub fn new_label(&mut self, name: String) -> usize {
        assert!(!name.contains(' '), "use underscores in label names, not spaces");

        // This label doesn't have an address yet
        self.label_addrs.push(0);
        self.label_names.push(name);

        return self.label_addrs.len() - 1;
    }

    /// Write a label at the current address
    pub fn write_label(&mut self, label_idx: usize) {
        self.label_addrs[label_idx] = self.write_pos;
    }

    // Add a label reference at the current write position
    pub fn label_ref(&mut self, label_idx: usize, num_bytes: usize, encode: fn(&mut CodeBlock, i64, i64)) {
        assert!(label_idx < self.label_addrs.len());

        // Keep track of the reference
        self.label_refs.push(LabelRef { pos: self.write_pos, label_idx, num_bytes, encode });

        // Move past however many bytes the instruction takes up
        if self.has_capacity(num_bytes) {
            self.write_pos += num_bytes;
        } else {
            self.dropped_bytes = true; // retry emitting the Insn after next_page
        }
    }

    // Link internal label references
    pub fn link_labels(&mut self) {
        let orig_pos = self.write_pos;

        // For each label reference
        for label_ref in mem::take(&mut self.label_refs) {
            let ref_pos = label_ref.pos;
            let label_idx = label_ref.label_idx;
            assert!(ref_pos < self.mem_size);

            let label_addr = self.label_addrs[label_idx];
            assert!(label_addr < self.mem_size);

            self.set_pos(ref_pos);
            (label_ref.encode)(self, (ref_pos + label_ref.num_bytes) as i64, label_addr as i64);

            // Assert that we've written the same number of bytes that we
            // expected to have written.
            assert!(self.write_pos == ref_pos + label_ref.num_bytes);
        }

        self.write_pos = orig_pos;

        // Clear the label positions and references
        self.label_addrs.clear();
        self.label_names.clear();
        assert!(self.label_refs.is_empty());
    }

    pub fn clear_labels(&mut self) {
        self.label_addrs.clear();
        self.label_names.clear();
        self.label_refs.clear();
    }

    pub fn get_label_state(&self) -> LabelState {
        LabelState {
            label_addrs: self.label_addrs.clone(),
            label_names: self.label_names.clone(),
            label_refs: self.label_refs.clone(),
        }
    }

    pub fn set_label_state(&mut self, state: LabelState) {
        self.label_addrs = state.label_addrs;
        self.label_names = state.label_names;
        self.label_refs = state.label_refs;
    }

    pub fn mark_all_writeable(&mut self) {
        self.mem_block.borrow_mut().mark_all_writeable();
    }

    pub fn mark_all_executable(&mut self) {
        self.mem_block.borrow_mut().mark_all_executable();
    }

    /// Code GC. Free code pages that are not on stack and reuse them.
    pub fn code_gc(&mut self, ocb: &mut OutlinedCb) {
        assert!(self.inline(), "must use on inline code block");

        // The previous code GC failed to free any pages. Give up.
        if self.freed_pages.as_ref() == &Some(vec![]) {
            return;
        }

        // Check which pages are still in use
        let mut pages_in_use = vec![false; self.num_mapped_pages()];
        // For each ISEQ, we currently assume that only code pages used by inline code
        // are used by outlined code, so we mark only code pages used by inlined code.
        for_each_on_stack_iseq_payload(|iseq_payload| {
            for page in &iseq_payload.pages {
                pages_in_use[*page] = true;
            }
        });
        // Avoid accumulating freed pages for future code GC
        for_each_off_stack_iseq_payload(|iseq_payload: &mut IseqPayload| {
            iseq_payload.pages = std::collections::HashSet::default();
        });
        // Outlined code generated by CodegenGlobals::init() should also be kept.
        for page in CodegenGlobals::get_ocb_pages() {
            pages_in_use[*page] = true;
        }

        // Invalidate everything to have more compact code after code GC.
        // This currently patches every ISEQ, which works, but in the future,
        // we could limit that to patch only on-stack ISEQs for optimizing code GC.
        rb_yjit_tracing_invalidate_all();

        // Assert that all code pages are freeable
        assert_eq!(
            0,
            self.mem_size % self.page_size,
            "end of the last code page should be the end of the entire region"
        );

        // Let VirtuamMem free the pages
        let mut freed_pages: Vec<usize> = pages_in_use.iter().enumerate()
            .filter(|&(_, &in_use)| !in_use).map(|(page, _)| page).collect();
        // ObjectSpace API may trigger Ruby's GC, which marks gc_offsets in JIT code.
        // So this should be called after for_each_*_iseq_payload and rb_yjit_tracing_invalidate_all.
        self.free_pages(&freed_pages);

        // Append virtual pages in case RubyVM::YJIT.code_gc is manually triggered.
        let mut virtual_pages: Vec<usize> = (self.num_mapped_pages()..self.num_virtual_pages()).collect();
        freed_pages.append(&mut virtual_pages);

        if let Some(&first_page) = freed_pages.first() {
            for cb in [&mut *self, ocb.unwrap()] {
                cb.write_pos = cb.get_page_pos(first_page);
                cb.past_page_bytes = 0;
                cb.dropped_bytes = false;
                cb.clear_comments();
            }
        }

        // Track which pages are free.
        let new_freed_pages = Rc::new(Some(freed_pages));
        let old_freed_pages = mem::replace(&mut self.freed_pages, Rc::clone(&new_freed_pages));
        ocb.unwrap().freed_pages = new_freed_pages;
        assert_eq!(1, Rc::strong_count(&old_freed_pages)); // will deallocate

        incr_counter!(code_gc_count);
    }

    pub fn inline(&self) -> bool {
        !self.outlined
    }

    pub fn other_cb(&self) -> Option<&'static mut Self> {
        if !CodegenGlobals::has_instance() {
            None
        } else if self.inline() {
            Some(CodegenGlobals::get_outlined_cb().unwrap())
        } else {
            Some(CodegenGlobals::get_inline_cb())
        }
    }
}

#[cfg(test)]
impl CodeBlock {
    /// Stubbed CodeBlock for testing. Can't execute generated code.
    pub fn new_dummy(mem_size: usize) -> Self {
        use std::ptr::NonNull;
        use crate::virtualmem::*;
        use crate::virtualmem::tests::TestingAllocator;

        let alloc = TestingAllocator::new(mem_size);
        let mem_start: *const u8 = alloc.mem_start();
        let virt_mem = VirtualMem::new(alloc, 1, NonNull::new(mem_start as *mut u8).unwrap(), mem_size, 128 * 1024 * 1024);

        Self::new(Rc::new(RefCell::new(virt_mem)), false, Rc::new(None), true)
    }

    /// Stubbed CodeBlock for testing conditions that can arise due to code GC. Can't execute generated code.
    #[cfg(target_arch = "aarch64")]
    pub fn new_dummy_with_freed_pages(mut freed_pages: Vec<usize>) -> Self {
        use std::ptr::NonNull;
        use crate::virtualmem::*;
        use crate::virtualmem::tests::TestingAllocator;

        freed_pages.sort_unstable();
        let mem_size = Self::PREFERRED_CODE_PAGE_SIZE *
            (1 + freed_pages.last().expect("freed_pages vec should not be empty"));

        let alloc = TestingAllocator::new(mem_size);
        let mem_start: *const u8 = alloc.mem_start();
        let virt_mem = VirtualMem::new(alloc, 1, NonNull::new(mem_start as *mut u8).unwrap(), mem_size, 128 * 1024 * 1024);

        Self::new(Rc::new(RefCell::new(virt_mem)), false, Rc::new(Some(freed_pages)), true)
    }
}

/// Produce hex string output from the bytes in a code block
impl fmt::LowerHex for CodeBlock {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let mem_block = &*self.mem_block.borrow();
            let byte = unsafe { mem_block.start_ptr().raw_ptr(mem_block).add(pos).read() };
            fmtr.write_fmt(format_args!("{:02x}", byte))?;
        }
        Ok(())
    }
}

impl crate::virtualmem::CodePtrBase for CodeBlock {
    fn base_ptr(&self) -> std::ptr::NonNull<u8> {
        self.mem_block.borrow().base_ptr()
    }
}

/// Wrapper struct so we can use the type system to distinguish
/// Between the inlined and outlined code blocks
pub struct OutlinedCb {
    // This must remain private
    cb: CodeBlock,
}

impl OutlinedCb {
    pub fn wrap(cb: CodeBlock) -> Self {
        OutlinedCb { cb: cb }
    }

    pub fn unwrap(&mut self) -> &mut CodeBlock {
        &mut self.cb
    }
}

/// Compute the number of bits needed to encode a signed value
pub fn imm_num_bits(imm: i64) -> u8
{
    // Compute the smallest size this immediate fits in
    if imm >= i8::MIN.into() && imm <= i8::MAX.into() {
        return 8;
    }
    if imm >= i16::MIN.into() && imm <= i16::MAX.into() {
        return 16;
    }
    if imm >= i32::MIN.into() && imm <= i32::MAX.into() {
        return 32;
    }

    return 64;
}

/// Compute the number of bits needed to encode an unsigned value
pub fn uimm_num_bits(uimm: u64) -> u8
{
    // Compute the smallest size this immediate fits in
    if uimm <= u8::MAX.into() {
        return 8;
    }
    else if uimm <= u16::MAX.into() {
        return 16;
    }
    else if uimm <= u32::MAX.into() {
        return 32;
    }

    return 64;
}

#[cfg(test)]
mod tests
{
    use super::*;

    #[test]
    fn test_imm_num_bits()
    {
        assert_eq!(imm_num_bits(i8::MIN.into()), 8);
        assert_eq!(imm_num_bits(i8::MAX.into()), 8);

        assert_eq!(imm_num_bits(i16::MIN.into()), 16);
        assert_eq!(imm_num_bits(i16::MAX.into()), 16);

        assert_eq!(imm_num_bits(i32::MIN.into()), 32);
        assert_eq!(imm_num_bits(i32::MAX.into()), 32);

        assert_eq!(imm_num_bits(i64::MIN), 64);
        assert_eq!(imm_num_bits(i64::MAX), 64);
    }

    #[test]
    fn test_uimm_num_bits() {
        assert_eq!(uimm_num_bits(u8::MIN.into()), 8);
        assert_eq!(uimm_num_bits(u8::MAX.into()), 8);

        assert_eq!(uimm_num_bits(((u8::MAX as u16) + 1).into()), 16);
        assert_eq!(uimm_num_bits(u16::MAX.into()), 16);

        assert_eq!(uimm_num_bits(((u16::MAX as u32) + 1).into()), 32);
        assert_eq!(uimm_num_bits(u32::MAX.into()), 32);

        assert_eq!(uimm_num_bits((u32::MAX as u64) + 1), 64);
        assert_eq!(uimm_num_bits(u64::MAX), 64);
    }

    #[test]
    fn test_code_size() {
        // Write 4 bytes in the first page
        let mut cb = CodeBlock::new_dummy(CodeBlock::PREFERRED_CODE_PAGE_SIZE * 2);
        cb.write_bytes(&[0, 0, 0, 0]);
        assert_eq!(cb.code_size(), 4);

        // Moving to the next page should not increase code_size
        assert!(cb.next_page(cb.get_write_ptr(), |_, _| {}));
        assert_eq!(cb.code_size(), 4);

        // Write 4 bytes in the second page
        cb.write_bytes(&[0, 0, 0, 0]);
        assert_eq!(cb.code_size(), 8);

        // Rewrite 4 bytes in the first page
        let old_write_pos = cb.get_write_pos();
        cb.set_pos(0);
        cb.write_bytes(&[1, 1, 1, 1]);

        // Moving from an old page to the next page should not increase code_size
        assert!(cb.next_page(cb.get_write_ptr(), |_, _| {}));
        cb.set_pos(old_write_pos);
        assert_eq!(cb.code_size(), 8);
    }
}
