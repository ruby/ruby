use std::cell::RefCell;
use std::cmp;
use std::fmt;
use std::mem;
use std::rc::Rc;
#[cfg(target_arch = "x86_64")]
use crate::backend::x86_64::JMP_PTR_BYTES;
#[cfg(target_arch = "aarch64")]
use crate::backend::arm64::JMP_PTR_BYTES;
use crate::backend::ir::Assembler;
use crate::backend::ir::Target;
use crate::virtualmem::WriteError;

#[cfg(feature = "asm_comments")]
use std::collections::BTreeMap;

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

    // Memory block size
    mem_size: usize,

    // Current writing position
    write_pos: usize,

    // Size of a code page (inlined + outlined)
    page_size: usize,

    // Size reserved for writing a jump to the next page
    page_end_reserve: usize,

    // Table of registered label addresses
    label_addrs: Vec<usize>,

    // Table of registered label names
    label_names: Vec<String>,

    // References to labels
    label_refs: Vec<LabelRef>,

    // Comments for assembly instructions, if that feature is enabled
    #[cfg(feature = "asm_comments")]
    asm_comments: BTreeMap<usize, Vec<String>>,

    // True for OutlinedCb
    pub outlined: bool,

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,
}

/// Set of CodeBlock label states. Used for recovering the previous state.
pub struct LabelState {
    label_addrs: Vec<usize>,
    label_names: Vec<String>,
    label_refs: Vec<LabelRef>,
}

impl CodeBlock {
    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>, page_size: usize, outlined: bool) -> Self {
        let mem_size = mem_block.borrow().virtual_region_size();
        let mut cb = Self {
            mem_block,
            mem_size,
            write_pos: 0,
            page_size,
            page_end_reserve: JMP_PTR_BYTES,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            #[cfg(feature = "asm_comments")]
            asm_comments: BTreeMap::new(),
            outlined,
            dropped_bytes: false,
        };
        cb.write_pos = cb.page_start();
        cb
    }

    /// Move the CodeBlock to the next page. If it's on the furthest page,
    /// move the other CodeBlock to the next page as well.
    pub fn next_page<F: Fn(&mut CodeBlock, CodePtr)>(&mut self, base_ptr: CodePtr, jmp_ptr: F) -> bool {
        let old_write_ptr = self.get_write_ptr();
        self.set_write_ptr(base_ptr);
        self.without_page_end_reserve(|cb| assert!(cb.has_capacity(JMP_PTR_BYTES)));

        // Move self to the next page
        let next_page_idx = self.write_pos / self.page_size + 1;
        if !self.set_page(next_page_idx, &jmp_ptr) {
            self.set_write_ptr(old_write_ptr); // rollback if there are no more pages
            return false;
        }

        // Move the other CodeBlock to the same page if it'S on the furthest page
        self.other_cb().unwrap().set_page(next_page_idx, &jmp_ptr);

        return !self.dropped_bytes;
    }

    /// Move the CodeBlock to page_idx only if it's not going backwards.
    fn set_page<F: Fn(&mut CodeBlock, CodePtr)>(&mut self, page_idx: usize, jmp_ptr: &F) -> bool {
        // Do not move the CodeBlock if page_idx points to an old position so that this
        // CodeBlock will not overwrite existing code.
        // TODO: We could move it to the last write_pos on that page if we keep track of
        // the past write_pos of each page.
        let mut dst_pos = self.page_size * page_idx + self.page_start();
        if self.page_size * page_idx < self.mem_size && self.write_pos < dst_pos {
            // Reset dropped_bytes
            self.dropped_bytes = false;

            // Convert dst_pos to dst_ptr
            let src_pos = self.write_pos;
            self.write_pos = dst_pos;
            let dst_ptr = self.get_write_ptr();
            self.write_pos = src_pos;

            // Generate jmp_ptr from src_pos to dst_pos
            self.without_page_end_reserve(|cb| {
                cb.add_comment("jump to next page");
                jmp_ptr(cb, dst_ptr);
                assert!(!cb.has_dropped_bytes());
            });

            // Start the next code from dst_pos
            self.write_pos = dst_pos;
        }
        !self.dropped_bytes
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
            start += JMP_PTR_BYTES;
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
    pub fn writable_addrs(&self, start_ptr: CodePtr, end_ptr: CodePtr) -> Vec<(usize, usize)> {
        let mut addrs = vec![];
        let mut start = start_ptr.raw_ptr() as usize;
        let codeblock_end = self.get_ptr(self.get_mem_size()).raw_ptr() as usize;
        let end = std::cmp::min(end_ptr.raw_ptr() as usize, codeblock_end);
        while start < end {
            let current_page = start / self.page_size * self.page_size;
            let page_end = std::cmp::min(end, current_page + self.page_end()) as usize;
            addrs.push((start, page_end));
            start = current_page + self.page_size + self.page_start();
        }
        addrs
    }

    /// Check if this code block has sufficient remaining capacity
    pub fn has_capacity(&self, num_bytes: usize) -> bool {
        let page_offset = self.write_pos % self.page_size;
        let capacity = self.page_end().saturating_sub(page_offset);
        num_bytes <= capacity
    }

    /// Add an assembly comment if the feature is on.
    /// If not, this becomes an inline no-op.
    #[cfg(feature = "asm_comments")]
    pub fn add_comment(&mut self, comment: &str) {
        let cur_ptr = self.get_write_ptr().into_usize();

        // If there's no current list of comments for this line number, add one.
        let this_line_comments = self.asm_comments.entry(cur_ptr).or_default();

        // Unless this comment is the same as the last one at this same line, add it.
        if this_line_comments.last().map(String::as_str) != Some(comment) {
            this_line_comments.push(comment.to_string());
        }
    }
    #[cfg(not(feature = "asm_comments"))]
    #[inline]
    pub fn add_comment(&mut self, _: &str) {}

    #[cfg(feature = "asm_comments")]
    pub fn comments_at(&self, pos: usize) -> Option<&Vec<String>> {
        self.asm_comments.get(&pos)
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
        let pos = code_ptr.into_usize() - self.mem_block.borrow().start_ptr().into_usize();
        self.set_pos(pos);
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.mem_block.borrow().start_ptr().add_bytes(offset)
    }

    /// Get a (possibly dangling) direct pointer to the current write position
    pub fn get_write_ptr(&self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, byte: u8) {
        let write_ptr = self.get_write_ptr();
        if !self.has_capacity(1) || self.mem_block.borrow_mut().write_byte(write_ptr, byte).is_err() {
            self.dropped_bytes = true;
        }

        // Always advance write_pos since arm64 PadEntryExit needs this to stop the loop.
        self.write_pos += 1;
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
        if !self.has_capacity(num_bytes) {
            self.dropped_bytes = true; // retry emitting the Insn after next_page
        }
        self.write_pos += num_bytes;
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

    pub fn mark_all_executable(&mut self) {
        self.mem_block.borrow_mut().mark_all_executable();
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
        use crate::virtualmem::*;
        use crate::virtualmem::tests::TestingAllocator;

        let alloc = TestingAllocator::new(mem_size);
        let mem_start: *const u8 = alloc.mem_start();
        let virt_mem = VirtualMem::new(alloc, 1, mem_start as *mut u8, mem_size);

        Self::new(Rc::new(RefCell::new(virt_mem)), 16 * 1024, false)
    }
}

/// Produce hex string output from the bytes in a code block
impl fmt::LowerHex for CodeBlock {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let byte = unsafe { self.mem_block.borrow().start_ptr().raw_ptr().add(pos).read() };
            fmtr.write_fmt(format_args!("{:02x}", byte))?;
        }
        Ok(())
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
}
