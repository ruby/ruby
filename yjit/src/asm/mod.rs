use std::fmt;
use std::mem;

#[cfg(feature = "asm_comments")]
use std::collections::BTreeMap;

use crate::virtualmem::{VirtualMem, CodePtr};

// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
pub mod x86_64;

pub mod arm64;

//
// TODO: need a field_size_of macro, to compute the size of a struct field in bytes
//

/// Reference to an ASM label
struct LabelRef {
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
    mem_block: VirtualMem,

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

    // Comments for assembly instructions, if that feature is enabled
    #[cfg(feature = "asm_comments")]
    asm_comments: BTreeMap<usize, Vec<String>>,

    // True for OutlinedCb
    #[cfg(feature = "disasm")]
    pub outlined: bool,

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,
}

impl CodeBlock {
    /// Make a new CodeBlock
    pub fn new(mem_block: VirtualMem, outlined: bool) -> Self {
        Self {
            mem_size: mem_block.virtual_region_size(),
            mem_block,
            write_pos: 0,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            #[cfg(feature = "asm_comments")]
            asm_comments: BTreeMap::new(),
            #[cfg(feature = "disasm")]
            outlined,
            dropped_bytes: false,
        }
    }

    /// Check if this code block has sufficient remaining capacity
    pub fn has_capacity(&self, num_bytes: usize) -> bool {
        self.write_pos + num_bytes < self.mem_size
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

    pub fn get_mem(&mut self) -> &mut VirtualMem {
        &mut self.mem_block
    }

    // Set the current write position
    pub fn set_pos(&mut self, pos: usize) {
        // No bounds check here since we can be out of bounds
        // when the code block fills up. We want to be able to
        // restore to the filled up state after patching something
        // in the middle.
        self.write_pos = pos;
    }

    // Align the current write pointer to a multiple of bytes
    pub fn align_pos(&mut self, multiple: u32) {
        // Compute the alignment boundary that is lower or equal
        // Do everything with usize
        let multiple: usize = multiple.try_into().unwrap();
        let pos = self.get_write_ptr().raw_ptr() as usize;
        let remainder = pos % multiple;
        let prev_aligned = pos - remainder;

        if prev_aligned == pos {
            // Already aligned so do nothing
        } else {
            // Align by advancing
            let pad = multiple - remainder;
            self.set_pos(self.get_write_pos() + pad);
        }
    }

    // Set the current write position from a pointer
    pub fn set_write_ptr(&mut self, code_ptr: CodePtr) {
        let pos = code_ptr.into_usize() - self.mem_block.start_ptr().into_usize();
        self.set_pos(pos);
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.mem_block.start_ptr().add_bytes(offset)
    }

    /// Get a (possibly dangling) direct pointer to the current write position
    pub fn get_write_ptr(&mut self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, byte: u8) {
        let write_ptr = self.get_write_ptr();

        if self.mem_block.write_byte(write_ptr, byte).is_ok() {
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

    /// Allocate a new label with a given name
    pub fn new_label(&mut self, name: String) -> usize {
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

    pub fn mark_all_executable(&mut self) {
        self.mem_block.mark_all_executable();
    }

    #[cfg(feature = "disasm")]
    pub fn inline(&self) -> bool {
        !self.outlined
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

        Self::new(virt_mem, false)
    }
}

/// Produce hex string output from the bytes in a code block
impl<'a> fmt::LowerHex for CodeBlock {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let byte = unsafe { self.mem_block.start_ptr().raw_ptr().add(pos).read() };
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

        assert_eq!(imm_num_bits(i64::MIN.into()), 64);
        assert_eq!(imm_num_bits(i64::MAX.into()), 64);
    }

    #[test]
    fn test_uimm_num_bits() {
        assert_eq!(uimm_num_bits(u8::MIN.into()), 8);
        assert_eq!(uimm_num_bits(u8::MAX.into()), 8);

        assert_eq!(uimm_num_bits(((u8::MAX as u16) + 1).into()), 16);
        assert_eq!(uimm_num_bits(u16::MAX.into()), 16);

        assert_eq!(uimm_num_bits(((u16::MAX as u32) + 1).into()), 32);
        assert_eq!(uimm_num_bits(u32::MAX.into()), 32);

        assert_eq!(uimm_num_bits(((u32::MAX as u64) + 1).into()), 64);
        assert_eq!(uimm_num_bits(u64::MAX.into()), 64);
    }
}
