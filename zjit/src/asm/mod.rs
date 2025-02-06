//use std::fmt;
use std::mem;
use std::collections::BTreeMap;

/*
use crate::core::IseqPayload;
use crate::core::for_each_off_stack_iseq_payload;
use crate::core::for_each_on_stack_iseq_payload;
use crate::invariants::rb_yjit_tracing_invalidate_all;
use crate::stats::incr_counter;
use crate::virtualmem::WriteError;
use crate::codegen::CodegenGlobals;
use crate::virtualmem::{VirtualMem, CodePtr};
*/




/// Pointer inside the ZJIT code region
#[derive(Eq, PartialEq)]
pub struct CodePtr(u32);









// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
pub mod x86_64;
pub mod arm64;







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
}

/// Set of CodeBlock label states. Used for recovering the previous state.
pub struct LabelState {
    label_addrs: Vec<usize>,
    label_names: Vec<String>,
    label_refs: Vec<LabelRef>,
}

impl CodeBlock {



    /// Add an assembly comment if the feature is on.
    pub fn add_comment(&mut self, _comment: &str) {
        /*
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
        */
    }

    /*
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
    */




    pub fn get_mem_size(&self) -> usize {
        self.mem_size
    }

    pub fn get_write_pos(&self) -> usize {
        self.write_pos
    }

    // Set the current write position
    pub fn set_pos(&mut self, pos: usize) {
        // No bounds check here since we can be out of bounds
        // when the code block fills up. We want to be able to
        // restore to the filled up state after patching something
        // in the middle.
        self.write_pos = pos;
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, _byte: u8) {
        /*
        let write_ptr = self.get_write_ptr();
        if self.has_capacity(1) && self.mem_block.borrow_mut().write_byte(write_ptr, byte).is_ok() {
            self.write_pos += 1;
        } else {
            self.dropped_bytes = true;
        }
        */
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

        /*
        // Move past however many bytes the instruction takes up
        if self.has_capacity(num_bytes) {
            self.write_pos += num_bytes;
        } else {
            self.dropped_bytes = true; // retry emitting the Insn after next_page
        }
        */
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


}


/*
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
*/

/*
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
*/



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