use std::collections::BTreeMap;
use std::fmt;
use std::ops::Range;
use std::rc::Rc;
use std::cell::RefCell;
use std::mem;
use crate::virtualmem::*;

// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
#[cfg(target_arch = "x86_64")]
pub mod x86_64;
#[cfg(target_arch = "aarch64")]
pub mod arm64;

/// Index to a label created by cb.new_label()
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct Label(pub usize);

/// Reference to an ASM label
#[derive(Clone)]
pub struct LabelRef {
    // Position in the code block where the label reference exists
    pos: usize,

    // Label which this refers to
    label: Label,

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

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,
}

impl CodeBlock {
    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>, keep_comments: bool) -> Self {
        let mem_size = mem_block.borrow().virtual_region_size();
        Self {
            mem_block,
            mem_size,
            write_pos: 0,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            keep_comments,
            asm_comments: BTreeMap::new(),
            dropped_bytes: false,
        }
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

    pub fn get_write_pos(&self) -> usize {
        self.write_pos
    }

    pub fn write_mem(&self, write_ptr: CodePtr, byte: u8) -> Result<(), WriteError> {
        self.mem_block.borrow_mut().write_byte(write_ptr, byte)
    }

    /// Get a (possibly dangling) direct pointer to the current write position
    pub fn get_write_ptr(&self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    /// Set the current write position from a pointer
    pub fn set_write_ptr(&mut self, code_ptr: CodePtr) {
        let pos = code_ptr.as_offset() - self.mem_block.borrow().start_ptr().as_offset();
        self.write_pos = pos.try_into().unwrap();
    }

    /// Invoke a callback with write_ptr temporarily adjusted to a given address
    pub fn with_write_ptr(&mut self, code_ptr: CodePtr, callback: impl Fn(&mut CodeBlock)) -> Range<CodePtr> {
        // Temporarily update the write_pos. Ignore the dropped_bytes flag at the old address.
        let old_write_pos = self.write_pos;
        let old_dropped_bytes = self.dropped_bytes;
        self.set_write_ptr(code_ptr);
        self.dropped_bytes = false;

        // Invoke the callback
        callback(self);

        // Build a code range modified by the callback
        let ret = code_ptr..self.get_write_ptr();

        // Restore the original write_pos and dropped_bytes flag.
        self.dropped_bytes = old_dropped_bytes;
        self.write_pos = old_write_pos;
        ret
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.mem_block.borrow().start_ptr().add_bytes(offset)
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, byte: u8) {
        let write_ptr = self.get_write_ptr();
        // TODO: check has_capacity()
        if self.mem_block.borrow_mut().write_byte(write_ptr, byte).is_ok() {
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
    pub fn write_int(&mut self, val: u64, num_bits: u32) {
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
    pub fn new_label(&mut self, name: String) -> Label {
        assert!(!name.contains(' '), "use underscores in label names, not spaces");

        // This label doesn't have an address yet
        self.label_addrs.push(0);
        self.label_names.push(name);

        Label(self.label_addrs.len() - 1)
    }

    /// Write a label at the current address
    pub fn write_label(&mut self, label: Label) {
        self.label_addrs[label.0] = self.write_pos;
    }

    // Add a label reference at the current write position
    pub fn label_ref(&mut self, label: Label, num_bytes: usize, encode: fn(&mut CodeBlock, i64, i64)) {
        assert!(label.0 < self.label_addrs.len());

        // Keep track of the reference
        self.label_refs.push(LabelRef { pos: self.write_pos, label, num_bytes, encode });

        // Move past however many bytes the instruction takes up
        if self.write_pos + num_bytes < self.mem_size {
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
            let label_idx = label_ref.label.0;
            assert!(ref_pos < self.mem_size);

            let label_addr = self.label_addrs[label_idx];
            assert!(label_addr < self.mem_size);

            self.write_pos = ref_pos;
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

    /// Convert a Label to CodePtr
    pub fn resolve_label(&self, label: Label) -> CodePtr {
        self.get_ptr(self.label_addrs[label.0])
    }

    pub fn clear_labels(&mut self) {
        self.label_addrs.clear();
        self.label_names.clear();
        self.label_refs.clear();
    }

    /// Make all the code in the region executable. Call this at the end of a write session.
    pub fn mark_all_executable(&mut self) {
        self.mem_block.borrow_mut().mark_all_executable();
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

#[cfg(test)]
impl CodeBlock {
    /// Stubbed CodeBlock for testing. Can't execute generated code.
    pub fn new_dummy() -> Self {
        use std::ptr::NonNull;
        use crate::virtualmem::*;
        use crate::virtualmem::tests::TestingAllocator;

        let mem_size = 1024;
        let alloc = TestingAllocator::new(mem_size);
        let mem_start: *const u8 = alloc.mem_start();
        let virt_mem = VirtualMem::new(alloc, 1, NonNull::new(mem_start as *mut u8).unwrap(), mem_size, 128 * 1024 * 1024);

        Self::new(Rc::new(RefCell::new(virt_mem)), false)
    }
}

impl crate::virtualmem::CodePtrBase for CodeBlock {
    fn base_ptr(&self) -> std::ptr::NonNull<u8> {
        self.mem_block.borrow().base_ptr()
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

/*
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
        cb.next_page(cb.get_write_ptr(), |_, _| {});
        assert_eq!(cb.code_size(), 4);

        // Write 4 bytes in the second page
        cb.write_bytes(&[0, 0, 0, 0]);
        assert_eq!(cb.code_size(), 8);

        // Rewrite 4 bytes in the first page
        let old_write_pos = cb.get_write_pos();
        cb.set_pos(0);
        cb.write_bytes(&[1, 1, 1, 1]);

        // Moving from an old page to the next page should not increase code_size
        cb.next_page(cb.get_write_ptr(), |_, _| {});
        cb.set_pos(old_write_pos);
        assert_eq!(cb.code_size(), 8);
    }
}

*/
