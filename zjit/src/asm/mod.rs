//! Model for creating generating textual assembler code.

use std::collections::BTreeMap;
use std::fmt;
use std::ops::Range;
use std::rc::Rc;
use std::cell::{RefCell, RefMut};
use std::mem;
use crate::state::update_zjit_compiling;
use crate::virtualmem::*;

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
type BranchEncoder = Box<dyn Fn(&mut CodeBlock, i64, i64) -> Result<(), ()>>;

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
pub struct CodeBlock<'mem> {
    // Memory for storing the encoded instructions
    mem_block: Rc<RefCell<VirtualMem>>,

    // Present only during a "scoped" CodeBlock. Its real lifetime is bound to
    // a local Rc in with_write_scope(), never extended or stored on the owner.
    mem_borrow: Option<RefMut<'mem, VirtualMem>>,
    base: std::ptr::NonNull<u8>,

    // Always >= write_pos. Nonempty only during a write scope; seeks and
    // permission changes invalidate it, including while a scope is active.
    writable_end: usize,

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

impl CodeBlock<'_> {
    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>, keep_comments: bool) -> Self {
        let mem_size = mem_block.borrow().virtual_region_size();
        let base = mem_block.borrow().base_ptr();

        Self {
            mem_block,
            mem_borrow: None,
            base,
            writable_end: 0,
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

    /// Establish an exclusive and persistent memory borrow for this closure.
    ///
    /// If scopes are nested they reuse the existing outer borrow; only the
    /// outermost scope releases it. No memory is mapped until a nonempty write.
    /// Progress and sticky failures survive both normal return and unwinding.
    ///
    /// The scoped CodeBlock has the same emission/inspection interface, but its
    /// borrow lifetime cannot escape through the closure's return value. There
    /// is no lifetime extension, self-reference, or manually paired end call.
    pub fn with_write_scope<R>(&mut self, emit: impl for<'scope> FnOnce(&mut CodeBlock<'scope>) -> R) -> R {
        if self.mem_borrow.is_some() {
            return emit(self);
        }

        // The Rc is local and outlives the real RefMut below. Moving the scoped
        // CodeBlock does not change that relationship, which Rust checks.
        let owner = self.mem_block.clone();
        let borrow = owner.borrow_mut();
        let scoped = CodeBlock {
            base: borrow.base_ptr(),
            mem_borrow: Some(borrow),
            mem_block: self.mem_block.clone(),
            mem_size: self.mem_size,
            write_pos: self.write_pos,
            writable_end: self.write_pos,
            label_addrs: mem::take(&mut self.label_addrs),
            label_names: mem::take(&mut self.label_names),
            label_refs: mem::take(&mut self.label_refs),
            keep_comments: self.keep_comments,
            asm_comments: mem::take(&mut self.asm_comments),
            dropped_bytes: self.dropped_bytes,
        };

        // Restore ALL ownership/state, not only the cursor: a closure receiving
        // &mut CodeBlock can replace that entire value. Memory and its metadata
        // must move back together, including on unwinding.
        struct Scope<'cb, 'owner, 'scope> {
            parent: &'cb mut CodeBlock<'owner>,
            scoped: Option<CodeBlock<'scope>>,
        }
        impl Drop for Scope<'_, '_, '_> {
            fn drop(&mut self) {
                *self.parent = self.scoped.take().unwrap().into_unscoped();
            }
        }
        let mut scope = Scope { parent: self, scoped: Some(scoped) };
        emit(scope.scoped.as_mut().unwrap())
    }

    /// Discard the borrowed lifetime by actually dropping its RefMut, then
    /// reconstruct the owning value. No borrowed references are kept.
    fn into_unscoped(mut self) -> CodeBlock<'static> {
        self.invalidate_write_span();
        self.mem_borrow = None;

        CodeBlock {
            mem_block: self.mem_block,
            mem_borrow: None,
            base: self.base,
            mem_size: self.mem_size,
            write_pos: self.write_pos,
            writable_end: self.write_pos,
            label_addrs: self.label_addrs,
            label_names: self.label_names,
            label_refs: self.label_refs,
            keep_comments: self.keep_comments,
            asm_comments: self.asm_comments,
            dropped_bytes: self.dropped_bytes,
        }
    }

    /// Write a single byte at the current position.
    #[inline]
    pub fn write_byte(&mut self, byte: u8) {
        // An empty span takes the slow path, which validates capacity before writing.
        if self.write_pos == self.writable_end {
            self.write_bytes_across_pages(&[byte]);
        } else {
            // A nonempty span implies an active exclusive borrow. Owner-side
            // seeks and permission changes invalidate it before changing state.
            unsafe { self.base.as_ptr().add(self.write_pos).write(byte) };
            self.write_pos += 1;
        }
    }

    /// Write multiple bytes starting from the current position.
    ///
    /// Stops at the first write failure, keeping the successfully written prefix.
    #[inline]
    pub fn write_bytes(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }

        if bytes.len() <= self.writable_end - self.write_pos {
            // The entire slice fits in the existing validated span.
            unsafe { self.copy_in_span(bytes) };
        } else {
            self.write_bytes_across_pages(bytes);
        }
    }

    /// Write an integer over the given number of bits at the current position.
    ///
    /// Write a little-endian integer, maintaining the per-call failure/retry contract:
    /// 16/32-bit slices, separate byte writes for other widths.
    #[inline]
    pub fn write_int(&mut self, val: u64, num_bits: u32) {
        assert!(num_bits > 0);
        assert!(num_bits % 8 == 0);

        // Switch on the number of bits
        match num_bits {
            8 => self.write_byte(val as u8),
            16 => self.write_bytes(&val.to_le_bytes()[..2]),
            32 => self.write_bytes(&val.to_le_bytes()[..4]),
            _ => {
                let mut cur = val;

                // Write out the bytes
                for _byte in 0..(num_bits / 8) {
                    self.write_byte(cur as u8);
                    cur >>= 8;
                }
            }
        }
    }

    /// Copy a nonempty slice that fits in the validated writable span.
    ///
    /// # Safety
    /// The caller must check a nonzero length <= writable_end - write_pos. A
    /// nonempty span implies a active RefMut. Seeking and permission changes
    /// invalidate the span before changing the corresponding state.
    unsafe fn copy_in_span(&mut self, bytes: &[u8]) {
        debug_assert!(!bytes.is_empty());
        debug_assert!(bytes.len() <= self.writable_end - self.write_pos);
        debug_assert!(self.mem_borrow.is_some());

        // Use an overlap-safe copy, as VirtualMemory::write_bytes does.
        unsafe { self.base.as_ptr().add(self.write_pos).copy_from(bytes.as_ptr(), bytes.len()) };
        self.write_pos += bytes.len();
    }

    #[inline(never)]
    fn write_bytes_across_pages(&mut self, mut bytes: &[u8]) {
        if self.mem_borrow.is_none() {
            // Unscoped writes hold their own short borrow for the entire VM
            // write, and never leave a cached span behind after releasing it.
            let mut mem = self.mem_block.borrow_mut();
            let ptr = mem.start_ptr().add_bytes(self.write_pos);
            let written = match mem.write_bytes(ptr, bytes) {
                Ok(()) => bytes.len(),
                Err(failure) => {
                    self.dropped_bytes = true;
                    failure.written
                }
            };

            self.write_pos += written;
            self.writable_end = self.write_pos;

            return;
        }

        while !bytes.is_empty() {
            if self.write_pos == self.writable_end && !self.prepare_next_span() {
                return;
            }

            let count = bytes.len().min(self.writable_end - self.write_pos);

            // A successful preparation gives a nonempty span. Copy only its
            // available prefix, committing progress before the next preparation.
            unsafe { self.copy_in_span(&bytes[..count]) };
            bytes = &bytes[count..];
        }
    }

    /// Lazily validate the next span. Ending a write at the boundary does not
    /// prepare the next page; failure leaves the cursor at the written prefix.
    #[inline(never)]
    fn prepare_next_span(&mut self) -> bool {
        debug_assert_eq!(self.write_pos, self.writable_end);

        let mem = self.mem_borrow.as_mut().expect("refill requires a write scope");
        match mem.prepare_write_span(self.write_pos) {
            Ok(available) => {
                debug_assert!(available > 0);

                // Preparation bounds available by region_size - write_pos.
                self.writable_end = self.write_pos + available;
                true
            }
            Err(_) => {
                self.dropped_bytes = true;
                false
            }
        }
    }

    /// Write a label at the current address
    pub fn write_label(&mut self, label: Label) {
        self.label_addrs[label.0] = self.write_pos;
    }

    // Add a label reference at the current write position
    pub fn label_ref(&mut self, label: Label, num_bytes: usize, encode: impl Fn(&mut CodeBlock, i64, i64) -> Result<(), ()> + 'static) {
        assert!(label.0 < self.label_addrs.len());

        // Keep track of the reference
        self.label_refs.push(LabelRef { pos: self.write_pos, label, num_bytes, encode: Box::new(encode) });

        // Move past however many bytes the instruction takes up.
        // Reserve the bytes by writing them rather than by moving the cursor
        // over them. Pages are mapped on first write, so a cursor bump alone
        // leaves a page that cannot be mapped.
        const RESERVED: [u8; 16] = [0; 16];
        assert!(num_bytes <= RESERVED.len(), "label reference wants {num_bytes} bytes");
        self.write_bytes(&RESERVED[..num_bytes]);
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

    fn invalidate_write_span(&mut self) {
        self.writable_end = self.write_pos;
    }

    // Inspection must use the cached borrow when a write scope is active.
    fn with_mem<R>(&self, inspect: impl FnOnce(&VirtualMem) -> R) -> R {
        match &self.mem_borrow {
            Some(borrow) => inspect(borrow),
            None => inspect(&self.mem_block.borrow()),
        }
    }

    // All owner-side memory mutations invalidate the cached span first, even
    // if the operation subsequently panics. Refills use the held borrow directly.
    fn with_mem_mut<R>(&mut self, mutate: impl FnOnce(&mut VirtualMem) -> R) -> R {
        self.invalidate_write_span();
        match &mut self.mem_borrow {
            Some(borrow) => mutate(borrow),
            None => mutate(&mut self.mem_block.borrow_mut()),
        }
    }

    /// Size of the region in bytes that we have allocated physical memory for.
    pub fn mapped_region_size(&self) -> usize {
        self.with_mem(|mem| mem.mapped_region_size())
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
        let pos = code_ptr.as_offset() - self.with_mem(|mem| mem.start_ptr()).as_offset();
        self.write_pos = pos.try_into().unwrap();
        self.invalidate_write_span();
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
        self.invalidate_write_span();
        ret
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.with_mem(|mem| mem.start_ptr()).add_bytes(offset)
    }

    /// Check if bytes have been dropped (unwritten because of insufficient space)
    pub fn has_dropped_bytes(&self) -> bool {
        self.dropped_bytes
    }

    /// Set dropped_bytes to false if the current zjit_alloc_bytes() + code_region_size
    /// + page_size is below --zjit-mem-size.
    pub fn update_dropped_bytes(&mut self) {
        // update_zjit_compiling reads the global owning CodeBlock, whose state
        // is restored only when the emission closure finishes.
        assert!(self.mem_borrow.is_none(), "update_dropped_bytes requires the owning CodeBlock");
        if self.with_mem(|mem| mem.can_allocate()) {
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

            self.set_write_ptr(self.get_ptr(ref_pos));
            let encode_result = self.with_write_scope(|cb| {
                (label_ref.encode.as_ref())(cb, (ref_pos + label_ref.num_bytes) as i64, label_addr as i64)
            });
            link_result = link_result.and(encode_result);

            // Verify number of bytes written when the callback returns Ok
            if encode_result.is_ok() {
                assert_eq!(self.write_pos, ref_pos + label_ref.num_bytes, "label_ref \
                    callback didn't write number of bytes it claimed to write upfront");
            }
        }

        self.write_pos = orig_pos;
        self.invalidate_write_span();

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
        self.with_mem_mut(|mem| mem.mark_all_writable());
    }

    pub fn mark_all_executable(&mut self) {
        self.with_mem_mut(|mem| mem.mark_all_executable());
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
impl fmt::LowerHex for CodeBlock<'_> {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let byte = self.with_mem(|mem| unsafe { mem.start_ptr().raw_ptr(mem).add(pos).read() });
            fmtr.write_fmt(format_args!("{byte:02x}"))?;
        }
        Ok(())
    }
}

#[cfg(test)]
impl CodeBlock<'_> {
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

impl crate::virtualmem::CodePtrBase for CodeBlock<'_> {
    fn base_ptr(&self) -> std::ptr::NonNull<u8> {
        self.with_mem(|mem| mem.base_ptr())
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
    use std::panic::{catch_unwind, AssertUnwindSafe};

    fn page_size() -> usize {
        unsafe { crate::cruby::rb_jit_get_page_size() as usize }
    }

    fn preparations(cb: &CodeBlock) -> usize {
        cb.with_mem(|mem| mem.write_span_preparations())
    }

    fn one_page_block() -> CodeBlock<'static> {
        let page = page_size();
        // Reserve two pages, but allow only the first to be mapped.
        let limit = crate::stats::zjit_alloc_bytes() + page + page / 2;
        let mem = VirtualMem::alloc(2 * page, Some(limit));
        CodeBlock::new(Rc::new(RefCell::new(mem)), true)
    }

    #[test]
    fn empty_writes_and_scopes_do_not_prepare_memory() {
        let mut cb = CodeBlock::new_dummy();

        let shared = cb.mem_block.clone();
        cb.write_bytes(&[]);

        cb.with_write_scope(|cb| {
            assert!(shared.try_borrow().is_err());
            assert!(shared.try_borrow_mut().is_err());

            cb.write_bytes(&[]);

            assert_eq!(cb.get_write_pos(), 0);
            assert_eq!(cb.mapped_region_size(), 0);
            assert!(!cb.has_dropped_bytes());
        });

        assert!(shared.try_borrow_mut().is_ok());
        assert_eq!(preparations(&cb), 0);
        assert_eq!(cb.mapped_region_size(), 0);
    }

    #[test]
    fn byte_and_integer_helpers_match_with_and_without_scope() {
        fn emit(cb: &mut CodeBlock) {
            cb.write_byte(0xaa);
            for bits in [8, 16, 24, 32, 64, 72] {
                cb.write_int(0x123456789abcdef0, bits);
            }

            assert_eq!(cb.get_write_pos(), 28);
            assert!(!cb.has_dropped_bytes());
        }

        let mut scoped = CodeBlock::new_dummy();
        let mut unscoped = CodeBlock::new_dummy();
        scoped.with_write_scope(emit);
        emit(&mut unscoped);

        assert_eq!(scoped.hexdump(), "aaf0f0def0debcf0debc9af0debc9a78563412f0debc9a7856341200");
        assert_eq!(scoped.hexdump(), unscoped.hexdump());
        assert_eq!(preparations(&scoped), 1);
        assert_eq!(preparations(&unscoped), 24);
        assert_eq!(unscoped.writable_end, unscoped.write_pos);
    }

    #[test]
    fn integer_byte_fallback_keeps_each_failed_attempt() {
        for scoped in [false, true] {
            let page = page_size();

            let mut cb = one_page_block();
            cb.set_write_ptr(cb.get_ptr(page - 3));

            let emit = |cb: &mut CodeBlock| {
                cb.write_int(0x123456789abcdef0, 64);
                assert_eq!(cb.get_write_pos(), page);
                assert!(cb.has_dropped_bytes());
                // Scoped: first page once + five failures. Unscoped: eight attempts.
                assert_eq!(preparations(cb), if scoped { 6 } else { 8 });
            };
            if scoped { cb.with_write_scope(emit); } else { emit(&mut cb); }

            let prefix = cb.get_ptr(page - 3).raw_ptr(&cb);
            assert_eq!(unsafe { std::slice::from_raw_parts(prefix, 3) }, &[0xf0, 0xde, 0xbc]);
        }
    }

    #[test]
    fn many_small_writes_prepare_once_per_page_and_refill_lazily() {
        let page = page_size();
        let mut cb = CodeBlock::new_dummy();

        cb.with_write_scope(|cb| {
            for _ in 0..page / 8 {
                cb.write_byte(1);
                cb.write_bytes(&[2, 3, 4, 5, 6, 7, 8]);
            }
            assert_eq!(cb.get_write_pos(), page);
            assert_eq!(cb.writable_end, page);
            assert_eq!(preparations(cb), 1);
            assert_eq!(cb.mapped_region_size(), page);

            cb.write_bytes(&[]);
            assert_eq!(preparations(cb), 1);

            cb.write_byte(9);
            assert_eq!(preparations(cb), 2);
            assert_eq!(cb.mapped_region_size(), 2 * page);
        });

        let actual = unsafe { std::slice::from_raw_parts(cb.get_ptr(0).raw_ptr(&cb), page + 1) };
        for chunk in actual[..page].chunks_exact(8) {
            assert_eq!(chunk, &[1, 2, 3, 4, 5, 6, 7, 8]);
        }
        assert_eq!(actual[page], 9);
    }

    #[test]
    fn invalid_start_fails_only_on_nonempty_write() {
        for scoped in [false, true] {
            let mut cb = CodeBlock::new_dummy();
            let end = cb.virtual_region_size();
            cb.set_write_ptr(cb.get_ptr(end));

            let emit = |cb: &mut CodeBlock| {
                cb.write_bytes(&[]);
                assert!(!cb.has_dropped_bytes());
                assert_eq!(preparations(cb), 0);

                cb.write_bytes(&[1, 2]);
                assert!(cb.has_dropped_bytes());
                assert_eq!(cb.get_write_pos(), end);
                assert_eq!(preparations(cb), 1);
            };
            if scoped { cb.with_write_scope(emit); } else { emit(&mut cb); }

            assert_eq!(cb.mapped_region_size(), 0);
        }
    }

    #[test]
    fn partial_progress_and_failures_are_live_and_sticky() {
        let page = page_size();
        let padding = vec![0xaa; page - 2];

        for scoped in [false, true] {
            let mut cb = one_page_block();
            let emit = |cb: &mut CodeBlock| {
                cb.write_bytes(&padding);
                assert!(!cb.has_dropped_bytes());

                cb.write_bytes(&[11, 22, 33, 44]);
                assert_eq!(cb.get_write_pos(), page);
                assert!(cb.has_dropped_bytes());

                let count = preparations(cb);
                cb.write_byte(55);
                assert_eq!(preparations(cb), count + 1);

                cb.write_bytes(&[]);
                assert_eq!(preparations(cb), count + 1);
            };
            if scoped { cb.with_write_scope(emit); } else { emit(&mut cb); }
            let ptr = cb.get_ptr(page - 2).raw_ptr(&cb);
            assert_eq!(unsafe { std::slice::from_raw_parts(ptr, 2) }, &[11, 22]);

            cb.set_write_ptr(cb.get_ptr(0));
            cb.with_write_scope(|cb| cb.write_byte(66));
            assert_eq!(cb.hexdump(), "42");
            assert!(cb.has_dropped_bytes());
        }
    }

    #[test]
    fn slices_match_vm_bulk_for_unaligned_and_cross_page_writes() {
        let page = page_size();

        for offset in [0, 1, page - 1, page, page + 1] {
            for len in [0, 1, 4, page - 1, page, page + 1, 2 * page + 3] {
                let input: Vec<u8> = (0..len).map(|i| (i % 251) as u8).collect();
                let mut bulk = CodeBlock::new_dummy_sized(6 * page);
                let mut cb = CodeBlock::new_dummy_sized(6 * page);
                bulk.set_write_ptr(bulk.get_ptr(offset));
                cb.set_write_ptr(cb.get_ptr(offset));

                let ptr = bulk.get_ptr(offset);
                bulk.mem_block.borrow_mut().write_bytes(ptr, &input).unwrap();

                bulk.write_pos += len;
                cb.with_write_scope(|cb| {
                    cb.write_bytes(&input);
                    let pages = if len == 0 { 0 } else { (offset + len - 1) / page - offset / page + 1 };

                    assert_eq!(preparations(cb), pages);
                });

                assert_eq!(cb.get_write_pos(), offset + len);
                assert_eq!(cb.mapped_region_size(), bulk.mapped_region_size());
                assert!(!cb.has_dropped_bytes());
                if len > 0 { assert_eq!(cb.hexdump(), bulk.hexdump()); }
            }
        }
    }

    #[test]
    fn live_addresses_comments_and_labels_work_without_reborrowing() {
        let mut cb = CodeBlock::new_dummy();
        cb.keep_comments = true;

        let label = cb.new_label("target");
        let start = cb.get_write_ptr();
        let base = cb.base_ptr();
        cb.with_write_scope(|cb| {
            assert_eq!(cb.base_ptr(), base);

            cb.add_comment("first");
            cb.add_comment("first");
            cb.write_byte(0xaa);
            cb.write_bytes(&[0xbb, 0xcc]);
            cb.write_label(label);

            assert_eq!(cb.get_write_ptr(), start.add_bytes(3));
            assert_eq!(cb.get_write_ptr().raw_addr(cb), base.as_ptr() as usize + 3);
            assert_eq!(cb.resolve_label(label), start.add_bytes(3));
            assert_eq!(cb.hexdump(), "aabbcc");
        });

        assert_eq!(cb.comments_at(start.raw_addr(&cb)).unwrap(), &["first"]);
        assert_eq!(cb.resolve_label(label), start.add_bytes(3));
    }

    #[test]
    fn nested_scopes_reuse_the_borrow_without_releasing_the_parent() {
        let mut cb = CodeBlock::new_dummy();
        let shared = cb.mem_block.clone();

        cb.with_write_scope(|cb| {
            cb.write_byte(1);
            let owners = Rc::strong_count(&shared);

            cb.with_write_scope(|cb| {
                assert_eq!(Rc::strong_count(&shared), owners);
                assert!(shared.try_borrow_mut().is_err());
                cb.write_bytes(&[2, 3]);
            });

            assert!(shared.try_borrow_mut().is_err());
            cb.write_byte(4);
            assert_eq!(preparations(cb), 1);
        });

        assert!(shared.try_borrow_mut().is_ok());
        assert_eq!(cb.hexdump(), "01020304");
    }

    #[test]
    fn a_caught_nested_panic_keeps_the_outer_borrow() {
        let mut cb = CodeBlock::new_dummy();
        let shared = cb.mem_block.clone();

        cb.with_write_scope(|cb| {
            assert!(catch_unwind(AssertUnwindSafe(|| cb.with_write_scope(|cb| {
                cb.write_byte(1);
                panic!("nested");
            }))).is_err());
            assert!(shared.try_borrow_mut().is_err());

            cb.write_byte(2);
            assert_eq!(preparations(cb), 1);
        });

        assert_eq!(cb.hexdump(), "0102");
        assert!(shared.try_borrow_mut().is_ok());
    }

    #[test]
    fn early_return_preserves_progress_and_releases_borrow() {
        let mut cb = CodeBlock::new_dummy();

        let result: Result<(), ()> = cb.with_write_scope(|cb| {
            cb.write_bytes(&[11, 22]);
            Err(())?;
            unreachable!()
        });

        assert_eq!(result, Err(()));
        assert_eq!(cb.hexdump(), "0b16");
        assert!(cb.mem_block.try_borrow_mut().is_ok());

        cb.write_byte(33);
        assert_eq!(cb.hexdump(), "0b1621");
    }

    #[test]
    fn unwinding_preserves_progress_labels_comments_and_releases_borrow() {
        let mut cb = CodeBlock::new_dummy();
        cb.keep_comments = true;

        let label = cb.new_label("target");
        let start = cb.get_ptr(0);

        assert!(catch_unwind(AssertUnwindSafe(|| cb.with_write_scope(|cb| {
            cb.add_comment("before panic");
            cb.label_ref(label, 4, |cb, _, _| { cb.write_bytes(&[1, 2, 3, 4]); Ok(()) });
            cb.write_byte(5);
            cb.write_label(label);
            panic!("interrupt emission");
        }))).is_err());

        assert_eq!(cb.get_write_pos(), 5);
        assert_eq!(cb.resolve_label(label), cb.get_ptr(5));
        assert_eq!(cb.comments_at(start.raw_addr(&cb)).unwrap(), &["before panic"]);
        assert!(cb.mem_block.try_borrow_mut().is_ok());
        cb.link_labels().unwrap();
        assert_eq!(cb.hexdump(), "0102030405");
    }

    #[test]
    fn conflicting_borrow_does_not_take_owner_metadata() {
        let mut cb = CodeBlock::new_dummy();
        let label = cb.new_label("target");

        cb.write_byte(1);
        cb.write_label(label);

        let shared = cb.mem_block.clone();
        let other = shared.borrow();
        assert!(catch_unwind(AssertUnwindSafe(|| cb.with_write_scope(|_| ()))).is_err());
        assert_eq!(cb.get_write_pos(), 1);
        assert_eq!(cb.resolve_label(label), cb.get_ptr(1));
        drop(other);

        cb.with_write_scope(|cb| cb.write_byte(2));
        assert_eq!(cb.hexdump(), "0102");
    }

    #[test]
    fn seeks_and_permission_changes_inside_scope_revalidate() {
        let page = page_size();
        let mut cb = CodeBlock::new_dummy();

        cb.with_write_scope(|cb| {
            cb.write_bytes(&[1, 2, 3, 4]);
            cb.mark_all_executable();
            assert_eq!(cb.writable_end, cb.write_pos);

            cb.set_write_ptr(cb.get_ptr(1));
            cb.write_byte(8);
            assert_eq!(preparations(cb), 2);

            cb.mark_all_writable();
            cb.write_byte(9);
            assert_eq!(preparations(cb), 3);

            cb.set_write_ptr(cb.get_ptr(page + 1));
            cb.write_byte(7);
            assert_eq!(preparations(cb), 4);

            cb.set_write_ptr(cb.get_ptr(3));
            cb.write_byte(6);
            assert_eq!(preparations(cb), 5);
            assert_eq!(cb.hexdump(), "01080906");
        });

        cb.mark_all_executable();
        cb.with_write_scope(|cb| cb.write_byte(5));
        assert_eq!(cb.hexdump(), "0108090605");
        assert_eq!(preparations(&cb), 6);
    }

    #[test]
    fn with_write_ptr_invalidates_both_patch_and_restored_positions() {
        let mut cb = CodeBlock::new_dummy();

        cb.with_write_scope(|cb| {
            cb.write_bytes(&[1, 2, 3, 4]);
            cb.mark_all_executable();
            let patch = cb.get_ptr(1);
            let range = cb.with_write_ptr(patch, |cb| {
                cb.with_write_scope(|cb| cb.write_bytes(&[8, 9]));
            });
            assert_eq!(range, patch..patch.add_bytes(2));

            assert_eq!(cb.get_write_pos(), 4);
            assert_eq!(cb.writable_end, 4);

            cb.write_byte(5);
            assert_eq!(preparations(cb), 3);
        });

        assert_eq!(cb.hexdump(), "0108090405");
    }

    #[test]
    fn multiple_code_blocks_can_share_memory_between_scopes() {
        let mut first = CodeBlock::new_dummy();
        let shared = first.mem_block.clone();
        let mut second = CodeBlock::new(shared.clone(), false);

        first.with_write_scope(|cb| {
            cb.write_byte(1);
            assert!(catch_unwind(AssertUnwindSafe(|| second.write_byte(2))).is_err());
            assert!(catch_unwind(AssertUnwindSafe(|| second.with_write_scope(|_| ()))).is_err());
            assert_eq!(second.get_write_pos(), 0);
        });

        second.write_byte(2);
        second.mark_all_executable();
        first.with_write_scope(|cb| cb.write_byte(3));
        assert_eq!(first.hexdump(), "0203");
        assert!(shared.try_borrow_mut().is_ok());
    }

    #[test]
    fn scoped_value_can_move_without_moving_the_borrowed_memory() {
        let mut cb = CodeBlock::new_dummy();
        let shared = cb.mem_block.clone();

        cb.with_write_scope(|cb| {
            let moved = std::mem::replace(cb, CodeBlock::new_dummy());
            let mut boxed = Box::new(moved);
            assert!(shared.try_borrow_mut().is_err());

            boxed.write_bytes(&[1, 2]);
            *cb = *boxed;
            cb.write_byte(3);
        });

        assert_eq!(cb.hexdump(), "010203");
        assert!(shared.try_borrow_mut().is_ok());
    }

    #[test]
    fn replacing_scoped_value_restores_memory_and_metadata_together() {
        for panic_after_replace in [false, true] {
            let mut cb = CodeBlock::new_dummy();
            let old_memory = cb.mem_block.clone();

            let result = catch_unwind(AssertUnwindSafe(|| cb.with_write_scope(|cb| {
                cb.write_byte(1);
                *cb = CodeBlock::new_dummy();
                cb.write_bytes(&[8, 9]);
                cb.with_write_scope(|cb| cb.write_byte(10));
                if panic_after_replace { panic!("after replacement"); }
            })));

            assert_eq!(result.is_err(), panic_after_replace);
            assert!(!Rc::ptr_eq(&cb.mem_block, &old_memory));
            assert_eq!(cb.hexdump(), "08090a");
            assert!(old_memory.try_borrow_mut().is_ok());
            assert!(cb.mem_block.try_borrow_mut().is_ok());

            cb.with_write_scope(|cb| cb.write_byte(11));
            assert_eq!(cb.hexdump(), "08090a0b");
        }
    }

    #[test]
    fn scope_refreshes_base_after_external_memory_replacement() {
        let mut cb = CodeBlock::new_dummy();
        cb.with_write_scope(|cb| cb.write_byte(1));

        // Allocate before replacing so the new region cannot reuse the old base.
        let replacement = VirtualMem::alloc(cb.virtual_region_size(), None);
        *cb.mem_block.borrow_mut() = replacement;
        cb.set_write_ptr(cb.get_ptr(0));
        cb.with_write_scope(|cb| cb.write_bytes(&[2, 3]));
        assert_eq!(cb.hexdump(), "0203");
        assert_eq!(preparations(&cb), 1);
    }

    #[test]
    fn linking_inside_scope_keeps_outer_borrow_and_cursor_live() {
        let mut cb = CodeBlock::new_dummy();
        let shared = cb.mem_block.clone();

        cb.with_write_scope(|cb| {
            let label = cb.new_label("end");
            cb.label_ref(label, 4, |cb, end, dst| {
                assert_eq!((end, dst), (4, 5));
                cb.write_bytes(&[1, 2, 3, 4]);
                Ok(())
            });

            cb.write_byte(5);
            cb.write_label(label);
            cb.link_labels().unwrap();
            assert!(shared.try_borrow_mut().is_err());
            assert_eq!(cb.get_write_pos(), 5);

            cb.write_byte(6);
        });

        assert_eq!(cb.hexdump(), "010203040506");
        assert!(shared.try_borrow_mut().is_ok());
    }

    #[test]
    fn global_compilation_state_update_requires_the_owner() {
        // CI uses RUST_BACKTRACE=1; the expected panic's backtrace allocations can
        // exceed the default memory limit, preventing the owner from clearing
        // dropped_bytes. Use an unlimited budget so this test checks ownership,
        // not memory limits.
        let mem = VirtualMem::alloc(1024 * 1024, Some(usize::MAX));
        let mut cb = CodeBlock::new(Rc::new(RefCell::new(mem)), false);
        cb.dropped_bytes = true;

        assert!(catch_unwind(AssertUnwindSafe(|| cb.with_write_scope(|cb| {
            cb.update_dropped_bytes();
        }))).is_err());
        assert!(cb.has_dropped_bytes());
        assert!(cb.mem_block.try_borrow_mut().is_ok());
        cb.update_dropped_bytes();
        assert!(!cb.has_dropped_bytes());
    }

    #[test]
    fn panic_in_patch_releases_its_scope() {
        let mut cb = CodeBlock::new_dummy();

        let label = cb.new_label("end");
        cb.label_ref(label, 2, |cb, _, _| { cb.write_byte(1); panic!("patch"); });
        cb.write_label(label);

        assert!(catch_unwind(AssertUnwindSafe(|| cb.link_labels())).is_err());
        assert!(cb.mem_block.try_borrow_mut().is_ok());
        assert_eq!(cb.get_write_pos(), 1);
        assert_eq!(cb.hexdump(), "01");
    }

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

            cb.with_write_scope(|cb| cb.label_ref(label, 4, move |cb, end, dst| {
                assert!(shared.try_borrow_mut().is_err());
                assert_eq!(cb.get_write_pos(), offset);
                assert_eq!(end, (offset + 4) as i64);
                assert_eq!(dst, (page_size + 16) as i64);
                cb.write_bytes(&[1, 2, 3, 4]);
                assert_eq!(cb.get_write_pos(), offset + 4);
                Ok(())
            }));
        }

        cb.set_write_ptr(cb.get_ptr(page_size + 16));
        cb.write_label(label);
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
        cb.with_write_scope(|cb| {
            cb.label_ref(label, 4, |cb, _, _| {
                // Failed encoders can fail before filling their reservations
                cb.write_byte(0xaa);
                Err(())
            });

            cb.label_ref(label, 4, |cb, _, _| {
                cb.write_bytes(&[1, 2, 3, 4]);
                Ok(())
            });

            cb.write_label(label);
        });

        // Seed a pre-existing write failure; encoder Err(()) is a separate error.
        // Linking must preserve this flag through every patch scope.
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
    fn link_labels_checks_successful_patch_length_after_end() {
        let mut cb = CodeBlock::new_dummy();
        let label = cb.new_label("target");

        cb.with_write_scope(|cb| cb.label_ref(label, 4, |cb, _, _| {
            cb.write_byte(1);
            Ok(())
        }));
        cb.link_labels().unwrap();
    }

    #[test]
    fn link_labels_commits_patch_failure_and_restores_position() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let mut cb = CodeBlock::new_dummy_sized(2 * page_size);
        let label = cb.new_label("target");

        cb.set_write_ptr(cb.get_ptr(page_size - 2));

        // Reserve only the writable prefix, then let the encoder overrun.
        cb.with_write_scope(|cb| cb.label_ref(label, 2, |cb, _, _| {
            cb.write_bytes(&[1, 2, 3, 4]);
            assert!(cb.has_dropped_bytes());
            assert_eq!(cb.get_write_pos(), cb.virtual_region_size() / 2);
            Err(())
        }));

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
        cb.with_write_scope(|cb| {
            for _ in 0..(page_size - 2) {
                cb.write_byte(0x90);
            }
        });
        assert!(!cb.has_dropped_bytes(), "the first page must map");

        // label_ref() must reserve its bytes by writing them, so that the
        // unmappable page surfaces as dropped_bytes here, where the caller
        // still reads it and turns it into CompileError::OutOfMemory.
        let label = cb.new_label("over_the_page_boundary");
        cb.with_write_scope(|cb| cb.label_ref(label, 5, |cb, _, _| {
            cb.write_bytes(&[0; 5]);
            Ok(())
        }));
        cb.write_label(label);

        // Mirror what compile_with_regs does after emit. It calls link_labels()
        // only if emit did not go OOM. This reproduces an assertion failure in
        // link_labels() when dropped_bytes isn't updated properly.
        if !cb.has_dropped_bytes() {
            cb.link_labels().unwrap();
        }
        assert!(cb.has_dropped_bytes(), "the reservation must discover the unmappable page");
    }
}
