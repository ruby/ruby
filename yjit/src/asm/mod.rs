use std::mem;

#[cfg(feature = "asm_comments")]
use std::collections::BTreeMap;

// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
#[cfg(target_arch = "x86_64")]
pub mod x86_64;
#[cfg(target_arch = "x86_64")]
pub use x86_64::*;
#[cfg(target_arch = "aarch64")]
pub mod aarch64;
#[cfg(target_arch = "aarch64")]
pub use aarch64::*;

/// Pointer to a piece of machine code
/// We may later change this to wrap an u32
/// Note: there is no NULL constant for CodePtr. You should use Option<CodePtr> instead.
#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Debug)]
#[repr(C)]
pub struct CodePtr(*const u8);

impl CodePtr {
    pub fn raw_ptr(&self) -> *const u8 {
        let CodePtr(ptr) = *self;
        return ptr;
    }

    fn into_i64(&self) -> i64 {
        let CodePtr(ptr) = self;
        *ptr as i64
    }

    #[allow(unused)]
    fn into_usize(&self) -> usize {
        let CodePtr(ptr) = self;
        *ptr as usize
    }
}

impl From<*mut u8> for CodePtr {
    fn from(value: *mut u8) -> Self {
        assert!(value as usize != 0);
        return CodePtr(value);
    }
}

//
// TODO: need a field_size_of macro, to compute the size of a struct field in bytes
//

// 1 is not aligned so this won't match any pages
const ALIGNED_WRITE_POSITION_NONE: usize = 1;

/// Reference to an ASM label
struct LabelRef {
    // Position in the code block where the label reference exists
    pos: usize,

    // Label which this refers to
    label_idx: usize,
}

/// Block of memory into which instructions can be assembled
pub struct CodeBlock {
    // Block of non-executable memory used for dummy code blocks
    // This memory is owned by this block and lives as long as the block
    #[allow(unused)]
    dummy_block: Vec<u8>,

    // Pointer to memory we are writing into
    mem_block: *mut u8,

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

    // Keep track of the current aligned write position.
    // Used for changing protection when writing to the JIT buffer
    current_aligned_write_pos: usize,

    // Memory protection works at page granularity and this is the
    // the size of each page. Used to implement W^X.
    page_size: usize,

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,
}

impl CodeBlock {
    #[cfg(test)]
    pub fn new_dummy(mem_size: usize) -> Self {
        // Allocate some non-executable memory
        let mut dummy_block = vec![0; mem_size];
        let mem_ptr = dummy_block.as_mut_ptr();

        Self {
            dummy_block: dummy_block,
            mem_block: mem_ptr,
            mem_size: mem_size,
            write_pos: 0,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            #[cfg(feature = "asm_comments")]
            asm_comments: BTreeMap::new(),
            current_aligned_write_pos: ALIGNED_WRITE_POSITION_NONE,
            page_size: 4096,
            dropped_bytes: false,
        }
    }

    #[cfg(not(test))]
    pub fn new(mem_block: *mut u8, mem_size: usize, page_size: usize) -> Self {
        Self {
            dummy_block: vec![0; 0],
            mem_block: mem_block,
            mem_size: mem_size,
            write_pos: 0,
            label_addrs: Vec::new(),
            label_names: Vec::new(),
            label_refs: Vec::new(),
            #[cfg(feature = "asm_comments")]
            asm_comments: BTreeMap::new(),
            current_aligned_write_pos: ALIGNED_WRITE_POSITION_NONE,
            page_size,
            dropped_bytes: false,
        }
    }

    // Check if this code block has sufficient remaining capacity
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

    // Set the current write position
    pub fn set_pos(&mut self, pos: usize) {
        // Assert here since while CodeBlock functions do bounds checking, there is
        // nothing stopping users from taking out an out-of-bounds pointer and
        // doing bad accesses with it.
        assert!(pos < self.mem_size);
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
        let pos = (code_ptr.raw_ptr() as usize) - (self.mem_block as usize);
        self.set_pos(pos);
    }

    // Get a direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        unsafe {
            let ptr = self.mem_block.add(offset);
            CodePtr(ptr)
        }
    }

    // Get a direct pointer to the current write position
    pub fn get_write_ptr(&mut self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    // Write a single byte at the current position
    pub fn write_byte(&mut self, byte: u8) {
        if self.write_pos < self.mem_size {
            self.mark_position_writable(self.write_pos);
            unsafe { self.mem_block.add(self.write_pos).write(byte) };
            self.write_pos += 1;
        } else {
            self.dropped_bytes = true;
        }
    }

    // Write multiple bytes starting from the current position
    pub fn write_bytes(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.write_byte(*byte);
        }
    }

    // Write a signed integer over a given number of bits at the current position
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
    pub fn new_label(&mut self, name: String) -> usize {
        // This label doesn't have an address yet
        self.label_addrs.push(0);
        self.label_names.push(name);

        return self.label_addrs.len() - 1;
    }

    /// Write a label at the current address
    pub fn write_label(&mut self, label_idx: usize) {
        // TODO: make sure that label_idx is valid
        // TODO: add an asseer here

        self.label_addrs[label_idx] = self.write_pos;
    }

    // Add a label reference at the current write position
    pub fn label_ref(&mut self, label_idx: usize) {
        // TODO: make sure that label_idx is valid
        // TODO: add an asseer here

        // Keep track of the reference
        self.label_refs.push(LabelRef {
            pos: self.write_pos,
            label_idx,
        });
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

            // Compute the offset from the reference's end to the label
            let offset = (label_addr as i64) - ((ref_pos + 4) as i64);

            self.set_pos(ref_pos);
            self.write_int(offset as u64, 32);
        }

        self.write_pos = orig_pos;

        // Clear the label positions and references
        self.label_addrs.clear();
        self.label_names.clear();
        assert!(self.label_refs.is_empty());
    }

    pub fn mark_position_writable(&mut self, write_pos: usize) {
        let page_size = self.page_size;
        let aligned_position = (write_pos / page_size) * page_size;

        if self.current_aligned_write_pos != aligned_position {
            self.current_aligned_write_pos = aligned_position;

            #[cfg(not(test))]
            unsafe {
                use core::ffi::c_void;
                let page_ptr = self.get_ptr(aligned_position).raw_ptr() as *mut c_void;
                crate::cruby::rb_yjit_mark_writable(page_ptr, page_size.try_into().unwrap());
            }
        }
    }

    pub fn mark_all_executable(&mut self) {
        self.current_aligned_write_pos = ALIGNED_WRITE_POSITION_NONE;

        #[cfg(not(test))]
        unsafe {
            use core::ffi::c_void;
            // NOTE(alan): Right now we do allocate one big chunck and give the top half to the outlined codeblock
            // The start of the top half of the region isn't necessarily a page boundary...
            let cb_start = self.get_ptr(0).raw_ptr() as *mut c_void;
            crate::cruby::rb_yjit_mark_executable(cb_start, self.mem_size.try_into().unwrap());
        }
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
