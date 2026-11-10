//! Model for creating generating textual assembler code.

use std::collections::BTreeMap;
use std::fmt;
use std::ops::Range;
use std::rc::Rc;
use std::cell::RefCell;
use std::mem;
use crate::state::update_zjit_compiling;
use crate::virtualmem::*;

mod code_writer;
pub use code_writer::CodeWriter;

// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
#[cfg(target_arch = "x86_64")]
pub mod x86_64;
#[cfg(target_arch = "aarch64")]
pub mod arm64;

/// Index to a label created by cb.new_label()
#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub struct Label(pub usize);

/// Name of a label, used for printing. It is `Copy` so that creating a label doesn't allocate.
#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub enum LabelName {
    /// Label of a LIR basic block lowered from an HIR basic block
    Block(crate::hir::BlockId, crate::backend::lir::BlockId),
    /// Label with a fixed name
    Static(&'static str),
}

impl From<&'static str> for LabelName {
    fn from(name: &'static str) -> Self {
        LabelName::Static(name)
    }
}

impl fmt::Display for LabelName {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            LabelName::Block(hir_block_id, lir_block_id) => write!(f, "{hir_block_id}_{lir_block_id}"),
            LabelName::Static(name) => write!(f, "{name}"),
        }
    }
}

/// The object that knows how to encode the branch instruction.
type BranchEncoder = Box<dyn Fn(&mut CodeWriter<'_>, i64, i64) -> Result<(), ()>>;

/// Reference to an ASM label
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
    encode: BranchEncoder,
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
    label_names: Vec<LabelName>,

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

    /// Size of the region in bytes that we have allocated physical memory for.
    pub fn mapped_region_size(&self) -> usize {
        self.mem_block.borrow().mapped_region_size()
    }

    /// Size of the region in bytes where writes could be attempted.
    pub fn virtual_region_size(&self) -> usize {
        self.mem_size
    }

    pub fn comments_at(&self, pos: usize) -> Option<&Vec<String>> {
        self.asm_comments.get(&pos)
    }

    pub fn get_write_pos(&self) -> usize {
        self.write_pos
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

    /// Check if bytes have been dropped (unwritten because of insufficient space)
    pub fn has_dropped_bytes(&self) -> bool {
        self.dropped_bytes
    }

    /// Set dropped_bytes to false if the current zjit_alloc_bytes() + code_region_size
    /// + page_size is below --zjit-mem-size.
    pub fn update_dropped_bytes(&mut self) {
        if self.mem_block.borrow().can_allocate() {
            self.dropped_bytes = false;

            // Memory is available again, so let the interpreter resume
            // triggering compilation.
            update_zjit_compiling();
        }
    }

    /// Allocate a new label with a given name
    pub fn new_label(&mut self, name: impl Into<LabelName>) -> Label {
        let name = name.into();
        if let LabelName::Static(name) = name {
            assert!(!name.contains(' '), "use underscores in label names, not spaces");
        }

        // This label doesn't have an address yet
        self.label_addrs.push(0);
        self.label_names.push(name);

        Label(self.label_addrs.len() - 1)
    }

    // Link internal label references
    pub fn link_labels(&mut self) -> Result<(), ()> {
        let orig_pos = self.write_pos;
        let mut link_result = Ok(());

        // For each label reference
        for label_ref in mem::take(&mut self.label_refs) {
            let ref_pos = label_ref.pos;
            let label_idx = label_ref.label.0;
            assert!(ref_pos < self.mem_size);

            let label_addr = self.label_addrs[label_idx];
            assert!(label_addr < self.mem_size);

            self.write_pos = ref_pos;
            let encode_result = {
                // Seeking invalidates any cached span. Each patch gets a fresh
                // writer, dropped before checking committed progress or seeking again.
                let mut writer = self.writer();
                (label_ref.encode.as_ref())(&mut writer, (ref_pos + label_ref.num_bytes) as i64, label_addr as i64)
            };
            link_result = link_result.and(encode_result);

            // Verify number of bytes written when the callback returns Ok
            if encode_result.is_ok() {
                assert_eq!(self.write_pos, ref_pos + label_ref.num_bytes, "label_ref \
                    callback didn't write number of bytes it claimed to write upfront");
            }
        }

        self.write_pos = orig_pos;

        // Clear the label positions and references
        self.label_addrs.clear();
        self.label_names.clear();
        assert!(self.label_refs.is_empty());

        link_result
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
    pub fn mark_all_writable(&mut self) {
        self.mem_block.borrow_mut().mark_all_writable();
    }

    pub fn mark_all_executable(&mut self) {
        self.mem_block.borrow_mut().mark_all_executable();
    }

    /// Call a func with the disasm of generated code for testing
    #[allow(unused_variables)]
    #[cfg(all(test, feature = "disasm"))]
    pub fn disasm(&self) -> String {
        let start_addr = self.get_ptr(0).raw_addr(self);
        let end_addr = self.get_write_ptr().raw_addr(self);
        crate::disasm::disasm_addr_range(self, start_addr, end_addr)
    }

    /// Return the hex dump of generated code for testing
    #[cfg(test)]
    pub fn hexdump(&self) -> String {
        format!("{:x}", self)
    }
}

/// Run assert_snapshot! only if cfg!(feature = "disasm").
/// $actual can be not only `cb.disasm()` but also `disasms!(cb1, cb2, ...)`.
#[cfg(test)]
#[macro_export]
macro_rules! assert_disasm_snapshot {
    ($actual: expr, @$($tt: tt)*) => {{
        #[cfg(feature = "disasm")]
        assert_snapshot!($actual, @$($tt)*)
    }};
}

/// Combine multiple cb.disasm() results to match all of them at once, which allows
/// us to avoid running the set of zjit-test -> zjit-test-update multiple times.
#[cfg(all(test, feature = "disasm"))]
#[macro_export]
macro_rules! disasms {
    ($( $cb:expr ),+ $(,)?) => {{
        crate::disasms_with!("", $( $cb ),+)
    }};
}

/// Basically `disasms!` but allows a non-"" delimiter, such as "\n"
#[cfg(all(test, feature = "disasm"))]
#[macro_export]
macro_rules! disasms_with {
    ($join:expr, $( $cb:expr ),+ $(,)?) => {{
        vec![$( $cb.disasm() ),+].join($join)
    }};
}

/// Combine multiple cb.hexdump() results to match all of them at once, which allows
/// us to avoid running the set of zjit-test -> zjit-test-update multiple times.
#[cfg(test)]
#[macro_export]
macro_rules! hexdumps {
    ($( $cb:expr ),+ $(,)?) => {{
        vec![$( $cb.hexdump() ),+].join("\n")
    }};
}

/// Produce hex string output from the bytes in a code block
impl fmt::LowerHex for CodeBlock {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let mem_block = &*self.mem_block.borrow();
            let byte = unsafe { mem_block.start_ptr().raw_ptr(mem_block).add(pos).read() };
            fmtr.write_fmt(format_args!("{byte:02x}"))?;
        }
        Ok(())
    }
}

#[cfg(test)]
impl CodeBlock {
    /// Stubbed CodeBlock for testing. Can't execute generated code.
    pub fn new_dummy() -> Self {
        const DEFAULT_MEM_SIZE: usize = 1024 * 1024;
        CodeBlock::new_dummy_sized(DEFAULT_MEM_SIZE)
    }

    pub fn new_dummy_sized(mem_size: usize) -> Self {
        use crate::virtualmem::*;
        let virt_mem = VirtualMem::alloc(mem_size, None);
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

    64
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

    64
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
    fn link_labels_revalidates_each_patch_and_restores_position() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let mut cb = CodeBlock::new_dummy();
        let label = cb.new_label("target");
        let shared = cb.mem_block.clone();

        // Deliberately register patches in nonsequential page order.
        for offset in [page_size + 8, 4, page_size - 2] {
            cb.set_write_ptr(cb.get_ptr(offset));
            let shared = shared.clone();

            cb.writer().label_ref(label, 4, move |writer, end, dst| {
                assert!(shared.try_borrow_mut().is_err());
                assert_eq!(writer.get_write_pos(), offset);
                assert_eq!(end, (offset + 4) as i64);
                assert_eq!(dst, (page_size + 16) as i64);
                writer.write_bytes(&[1, 2, 3, 4]);
                assert_eq!(writer.get_write_pos(), offset + 4);
                Ok(())
            });
        }

        cb.set_write_ptr(cb.get_ptr(page_size + 16));
        cb.writer().write_label(label);
        cb.mark_all_executable();

        let preparations = shared.borrow().write_span_preparations();
        cb.link_labels().unwrap();
        assert_eq!(cb.get_write_pos(), page_size + 16);
        assert!(!cb.has_dropped_bytes());

        // One fresh span per patch, plus the crossing patch's second page.
        assert_eq!(shared.borrow().write_span_preparations(), preparations + 4);
        for offset in [page_size + 8, 4, page_size - 2] {
            let ptr = cb.get_ptr(offset).raw_ptr(&cb);
            assert_eq!(unsafe { std::slice::from_raw_parts(ptr, 4) }, &[1, 2, 3, 4]);
        }

        assert!(cb.label_addrs.is_empty());
        assert!(cb.label_names.is_empty());
        assert!(cb.label_refs.is_empty());
        cb.mark_all_executable();
    }

    #[test]
    fn link_labels_keeps_errors_and_continues_patching() {
        let mut cb = CodeBlock::new_dummy();

        let label = cb.new_label("target");
        {
            let mut writer = cb.writer();

            writer.label_ref(label, 4, |writer, _, _| {
                // Failed encoders can fail before filling their reservations
                writer.write_byte(0xaa);
                Err(())
            });
            writer.label_ref(label, 4, |writer, _, _| {
                writer.write_bytes(&[1, 2, 3, 4]);
                Ok(())
            });

            writer.write_label(label);
        }

        // Seed a pre-existing write failure; encoder Err(()) is a separate error.
        // Linking must preserve this flag through every patch-writer scope.
        cb.dropped_bytes = true;
        assert_eq!(cb.link_labels(), Err(()));
        assert_eq!(cb.get_write_pos(), 8);
        assert!(cb.has_dropped_bytes());
        assert_eq!(cb.hexdump(), "aa00000001020304");

        assert!(cb.label_refs.is_empty());
        assert!(cb.label_addrs.is_empty());
        assert!(cb.label_names.is_empty());

        // Linking labels works since no pending references remain.
        assert_eq!(cb.link_labels(), Ok(()));
        // However dropped_bytes are not cleared.
        assert!(cb.has_dropped_bytes());
    }

    #[test]
    #[should_panic(expected = "callback didn't write number of bytes")]
    fn link_labels_checks_successful_patch_length_after_drop() {
        let mut cb = CodeBlock::new_dummy();
        let label = cb.new_label("target");

        cb.writer().label_ref(label, 4, |writer, _, _| {
            writer.write_byte(1);
            Ok(())
        });
        cb.link_labels().unwrap();
    }

    #[test]
    fn link_labels_commits_patch_failure_and_restores_position() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let mut cb = CodeBlock::new_dummy_sized(2 * page_size);
        let label = cb.new_label("target");

        cb.set_write_ptr(cb.get_ptr(page_size - 2));

        // Reserve only the writable prefix, then let the encoder overrun.
        cb.writer().label_ref(label, 2, |writer, _, _| {
            writer.write_bytes(&[1, 2, 3, 4]);
            assert!(writer.has_dropped_bytes());
            assert_eq!(writer.get_write_pos(), writer.virtual_region_size() / 2);
            Err(())
        });

        cb.set_write_ptr(cb.get_ptr(0));
        assert_eq!(cb.link_labels(), Err(()));
        assert_eq!(cb.get_write_pos(), 0);
        assert!(cb.has_dropped_bytes());

        let ptr = cb.get_ptr(page_size - 2).raw_ptr(&cb);
        assert_eq!(unsafe { std::slice::from_raw_parts(ptr, 2) }, &[1, 2]);
        assert!(cb.label_refs.is_empty());
        assert!(cb.mem_block.try_borrow_mut().is_ok());
    }

    #[test]
    fn test_label_ref_at_an_unmappable_page_sets_dropped_bytes() {
        // Two pages of address space, but a memory limit that only lets
        // the first page be mapped.
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let limit = crate::stats::zjit_alloc_bytes() + page_size + page_size / 2;
        let virt_mem = VirtualMem::alloc(2 * page_size, Some(limit));
        let mut cb = CodeBlock::new(Rc::new(RefCell::new(virt_mem)), false);

        // Fill the mappable page up to 2 bytes below its end, so that
        // a 5-byte jump reservation straddles into the unmappable page.
        {
            let mut writer = cb.writer();
            for _ in 0..(page_size - 2) {
                writer.write_byte(0x90);
            }
        }
        assert!(!cb.has_dropped_bytes(), "the first page must map");

        // label_ref() must reserve its bytes by writing them, so that the
        // unmappable page surfaces as dropped_bytes here, where the caller
        // still reads it and turns it into CompileError::OutOfMemory.
        let label = cb.new_label("over_the_page_boundary");
        cb.writer().label_ref(label, 5, |writer, _, _| {
            writer.write_bytes(&[0; 5]);
            Ok(())
        });
        cb.writer().write_label(label);

        // Mirror what compile_with_regs does after emit. It calls link_labels()
        // only if emit did not go OOM. This reproduces an assertion failure in
        // link_labels() when dropped_bytes isn't updated properly.
        if !cb.has_dropped_bytes() {
            cb.link_labels().unwrap();
        }
        assert!(cb.has_dropped_bytes(), "the reservation must discover the unmappable page");
    }
}
