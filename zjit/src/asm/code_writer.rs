//! A scoped emission cursor with an exclusive borrow of a CodeBlock's memory.

use std::cell::RefMut;
use std::collections::BTreeMap;
use std::ptr::NonNull;

use super::{CodeBlock, Label, LabelRef};
use crate::virtualmem::{CodePtr, CodePtrBase, VirtualMem};

/// Sequential emission into a code block. Position and failure state are live
/// here while the writer exists, and are committed to CodeBlock on drop.
///
/// This isn't meant as a transaction: successful writes stay in memory on failure
/// or unwinding. Dropping the writer does not change memory permissions. Linking
/// labels and invoking position-marker callbacks must happen after it is dropped.
pub struct CodeWriter<'a> {
    mem: RefMut<'a, VirtualMem>,
    base: NonNull<u8>,
    pos: usize,
    // Exclusive end of the validated writable span. Always >= pos; equality
    // means empty (including before the first write). The exclusive memory
    // borrow and absence of seek/permission APIs keep a cached span valid.
    writable_end: usize,
    dropped: bool,

    // Borrow disjoint fields, not the CodeBlock that owns the memory RefCell.
    final_pos: &'a mut usize,
    final_dropped: &'a mut bool,
    label_addrs: &'a mut Vec<usize>,
    label_refs: &'a mut Vec<LabelRef>,
    keep_comments: bool,
    asm_comments: &'a mut BTreeMap<usize, Vec<String>>,
}

impl CodeBlock {
    /// Borrow memory once for a sequence of writes. An empty session does not
    /// map memory. The block cannot be accessed until the writer is dropped.
    pub fn writer(&mut self) -> CodeWriter<'_> {
        let mem = self.mem_block.borrow_mut();
        let base = mem.base_ptr();
        CodeWriter {
            mem,
            base,
            pos: self.write_pos,
            writable_end: self.write_pos,
            dropped: self.dropped_bytes,
            final_pos: &mut self.write_pos,
            final_dropped: &mut self.dropped_bytes,
            label_addrs: &mut self.label_addrs,
            label_refs: &mut self.label_refs,
            keep_comments: self.keep_comments,
            asm_comments: &mut self.asm_comments,
        }
    }
}

impl CodeWriter<'_> {
    pub fn get_write_pos(&self) -> usize {
        self.pos
    }

    pub fn get_write_ptr(&self) -> CodePtr {
        self.mem.start_ptr().add_bytes(self.pos)
    }

    pub fn virtual_region_size(&self) -> usize {
        self.mem.virtual_region_size()
    }

    pub fn has_dropped_bytes(&self) -> bool {
        self.dropped
    }

    #[inline]
    pub fn write_byte(&mut self, byte: u8) {
        if self.pos == self.writable_end && !self.prepare_next_span() {
            return;
        }
        // The nonempty span is in bounds and writable. No other access to the
        // memory can invalidate it while this writer holds the exclusive borrow.
        unsafe { self.base.as_ptr().add(self.pos).write(byte) };
        self.pos += 1;
    }

    #[inline]
    pub fn write_bytes(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }

        if bytes.len() <= self.writable_end - self.pos {
            // The entire slice fits in the existing validated span.
            unsafe { self.copy_in_span(bytes) };
        } else {
            self.write_bytes_across_pages(bytes);
        }
    }

    /// Write a little-endian integer, maintaining the per-call failure/retry contract:
    /// 16/32-bit slices, separate byte writes for other widths.
    #[inline]
    pub fn write_int(&mut self, val: u64, num_bits: u32) {
        assert!(num_bits > 0);
        assert!(num_bits % 8 == 0);
        match num_bits {
            8 => self.write_byte(val as u8),
            16 => self.write_bytes(&val.to_le_bytes()[..2]),
            32 => self.write_bytes(&val.to_le_bytes()[..4]),
            _ => {
                let mut cur = val;
                for _ in 0..(num_bits / 8) {
                    self.write_byte(cur as u8);
                    cur >>= 8;
                }
            }
        }
    }

    /// Copy a nonempty slice that fits in the current validated writable span.
    ///
    /// # Safety
    /// The caller must check that bytes is nonempty and its length does not
    /// exceed writable_end - pos. Span validity is maintained by the writer:
    /// it retains exclusive memory access and never seeks or changes permissions.
    unsafe fn copy_in_span(&mut self, bytes: &[u8]) {
        debug_assert!(!bytes.is_empty());
        debug_assert!(bytes.len() <= self.writable_end - self.pos);

        // Use an overlap-safe copy, as VirtualMemory::write_bytes does.
        unsafe { self.base.as_ptr().add(self.pos).copy_from(bytes.as_ptr(), bytes.len()) };
        self.pos += bytes.len();
    }

    #[inline(never)]
    fn write_bytes_across_pages(&mut self, mut bytes: &[u8]) {
        while !bytes.is_empty() {
            if self.pos == self.writable_end && !self.prepare_next_span() {
                return;
            }
            let count = bytes.len().min(self.writable_end - self.pos);

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
        debug_assert_eq!(self.pos, self.writable_end);

        match self.mem.prepare_write_span(self.pos) {
            Ok(available) => {
                debug_assert!(available > 0);
                // Preparation bounds available by region_size - pos.
                self.writable_end = self.pos + available;
                true
            }
            Err(_) => {
                self.dropped = true;
                false
            }
        }
    }

    pub fn write_label(&mut self, label: Label) {
        self.label_addrs[label.0] = self.pos;
    }

    /// Record a patch encoder for later linking through CodeBlock, and reserve
    /// its bytes now so that mapping failures are visible during emission.
    pub fn label_ref(
        &mut self,
        label: Label,
        num_bytes: usize,
        encode: impl Fn(&mut CodeWriter<'_>, i64, i64) -> Result<(), ()> + 'static,
    ) {
        assert!(label.0 < self.label_addrs.len());
        self.label_refs.push(LabelRef { pos: self.pos, label, num_bytes, encode: Box::new(encode) });

        const RESERVED: [u8; 16] = [0; 16];
        assert!(num_bytes <= RESERVED.len(), "label reference wants {num_bytes} bytes");
        self.write_bytes(&RESERVED[..num_bytes]);
    }

    pub fn add_comment(&mut self, comment: &str) {
        if !self.keep_comments {
            return;
        }

        let addr = self.get_write_ptr().raw_addr(self);
        let comments = self.asm_comments.entry(addr).or_default();
        if comments.last().map(String::as_str) != Some(comment) {
            comments.push(comment.to_string());
        }
    }
}

impl CodePtrBase for CodeWriter<'_> {
    fn base_ptr(&self) -> NonNull<u8> {
        self.base
    }
}

impl Drop for CodeWriter<'_> {
    fn drop(&mut self) {
        *self.final_pos = self.pos;
        *self.final_dropped = self.dropped;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::rc::Rc;

    fn one_page_block() -> (CodeBlock, usize) {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let limit = crate::stats::zjit_alloc_bytes() + page_size + page_size / 2;
        let mem = VirtualMem::alloc(2 * page_size, Some(limit));
        (CodeBlock::new(Rc::new(RefCell::new(mem)), true), page_size)
    }

    #[test]
    fn test_write_bytes_success_and_empty() {
        let mut cb = CodeBlock::new_dummy();

        cb.writer().write_bytes(&[]);
        assert_eq!(cb.get_write_pos(), 0);
        assert!(!cb.has_dropped_bytes());

        cb.writer().write_bytes(&[11, 22, 33]);
        assert_eq!(cb.get_write_pos(), 3);
        assert!(!cb.has_dropped_bytes());

        cb.writer().write_bytes(&[]);
        assert_eq!(cb.get_write_pos(), 3);
        assert!(!cb.has_dropped_bytes());
    }

    #[test]
    fn test_write_bytes_partial_failure_and_sticky_dropped_bytes() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let padding = vec![0xaa; page_size - 2];
        let limit = crate::stats::zjit_alloc_bytes() + page_size + page_size / 2;
        let virt_mem = VirtualMem::alloc(2 * page_size, Some(limit));
        let mut cb = CodeBlock::new(Rc::new(RefCell::new(virt_mem)), false);

        cb.writer().write_bytes(&padding);
        assert!(!cb.has_dropped_bytes());

        cb.writer().write_bytes(&[11, 22, 33, 44]);
        assert_eq!(cb.get_write_pos(), page_size);
        assert!(cb.has_dropped_bytes());

        // Already at the unmappable page: no progress on another failed write.
        cb.writer().write_bytes(&[55]);
        assert_eq!(cb.get_write_pos(), page_size);
        assert!(cb.has_dropped_bytes());

        cb.writer().write_bytes(&[]);
        assert_eq!(cb.get_write_pos(), page_size);
        assert!(cb.has_dropped_bytes());

        // A successful overwrite must not clear the earlier failure.
        cb.set_write_ptr(cb.get_ptr(0));
        cb.writer().write_bytes(&[66]);
        assert_eq!(cb.get_write_pos(), 1);
        assert!(cb.has_dropped_bytes());
    }

    #[test]
    fn byte_and_integer_helpers_reuse_span() {
        fn emit(writer: &mut CodeWriter<'_>) {
            writer.write_byte(0xaa);
            for bits in [8, 16, 24, 32, 64, 72] {
                writer.write_int(0x123456789abcdef0, bits);
            }
        }
        let mut cb = CodeBlock::new_dummy();

        {
            let mut writer = cb.writer();
            emit(&mut writer);

            assert_eq!(writer.mem.write_span_preparations(), 1);
            assert_eq!(writer.get_write_pos(), 28);
            assert!(!writer.has_dropped_bytes());
        }
        assert_eq!(cb.hexdump(), "aaf0f0def0debcf0debc9af0debc9a78563412f0debc9a7856341200");
    }

    #[test]
    fn integer_byte_fallback_preserves_partial_progress() {
        let (mut cb, page_size) = one_page_block();
        cb.set_write_ptr(cb.get_ptr(page_size - 3));

        {
            let mut writer = cb.writer();
            writer.write_int(0x123456789abcdef0, 64);
            assert_eq!(writer.get_write_pos(), page_size);
            assert!(writer.has_dropped_bytes());
            // First page once, then one failed preparation for each remaining byte.
            assert_eq!(writer.mem.write_span_preparations(), 6);
        }

        let prefix = cb.get_ptr(page_size - 3).raw_ptr(&cb);
        assert_eq!(unsafe { std::slice::from_raw_parts(prefix, 3) }, &[0xf0, 0xde, 0xbc]);
    }

    #[test]
    fn empty_session_does_not_map_memory() {
        let mut cb = CodeBlock::new_dummy();

        {
            let mut writer = cb.writer();
            writer.write_bytes(&[]);
            assert_eq!(writer.get_write_pos(), 0);
            assert!(!writer.has_dropped_bytes());
        }

        assert_eq!(cb.mapped_region_size(), 0);
        assert_eq!(cb.mem_block.borrow().write_span_preparations(), 0);
        assert_eq!(cb.get_write_pos(), 0);
        assert!(!cb.has_dropped_bytes());
    }

    #[test]
    fn many_small_writes_prepare_once_per_page_and_refill_lazily() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let mut cb = CodeBlock::new_dummy();

        {
            let mut writer = cb.writer();

            for _ in 0..page_size / 8 {
                writer.write_byte(1);
                writer.write_bytes(&[2, 3, 4, 5, 6, 7, 8]);
            }

            assert_eq!(writer.get_write_pos(), page_size);
            assert_eq!(writer.writable_end, page_size);
            assert_eq!(writer.mem.write_span_preparations(), 1);
            assert_eq!(writer.mem.mapped_region_size(), page_size);

            // Neither finishing exactly at the boundary nor an empty write
            // should prepare or allocate the next page.
            writer.write_bytes(&[]);
            assert_eq!(writer.mem.write_span_preparations(), 1);
            assert_eq!(writer.mem.mapped_region_size(), page_size);

            writer.write_byte(9);
            assert_eq!(writer.get_write_pos(), page_size + 1);
            assert_eq!(writer.mem.write_span_preparations(), 2);
            assert_eq!(writer.mem.mapped_region_size(), 2 * page_size);
        }

        let actual = unsafe { std::slice::from_raw_parts(cb.get_ptr(0).raw_ptr(&cb), page_size + 1) };
        for chunk in actual[..page_size].chunks_exact(8) {
            assert_eq!(chunk, &[1, 2, 3, 4, 5, 6, 7, 8]);
        }
        assert_eq!(actual[page_size], 9);
    }

    #[test]
    fn invalid_start_fails_only_on_a_nonempty_write() {
        let mut cb = CodeBlock::new_dummy();
        let end = cb.virtual_region_size();
        cb.set_write_ptr(cb.get_ptr(end));

        {
            let mut writer = cb.writer();

            writer.write_bytes(&[]);
            assert!(!writer.has_dropped_bytes());
            assert_eq!(writer.mem.write_span_preparations(), 0);

            writer.write_bytes(&[1, 2]);
            assert!(writer.has_dropped_bytes());
            assert_eq!(writer.get_write_pos(), end);
            assert_eq!(writer.writable_end, end);
            assert_eq!(writer.mem.write_span_preparations(), 1);
        }

        assert_eq!(cb.mapped_region_size(), 0);
    }

    #[test]
    fn a_new_session_revalidates_after_permission_changes() {
        let mut cb = CodeBlock::new_dummy();
        let shared_mem = cb.mem_block.clone();

        {
            let mut writer = cb.writer();

            // Even another owner of the memory cannot safely change permissions
            // while this writer is using its cached span.
            assert!(shared_mem.try_borrow_mut().is_err());

            writer.write_byte(1);
            assert_eq!(writer.mem.write_span_preparations(), 1);
        }

        cb.mark_all_executable();

        {
            let mut writer = cb.writer();
            assert_eq!(writer.pos, writer.writable_end);

            writer.write_byte(2);
            assert_eq!(writer.mem.write_span_preparations(), 2);
        }

        assert_eq!(cb.hexdump(), "0102");
    }

    #[test]
    fn live_position_and_base_are_available_without_reborrowing() {
        let mut cb = CodeBlock::new_dummy();
        cb.keep_comments = true;
        cb.writer().write_byte(0xaa);
        let start = cb.get_write_ptr();
        let base = cb.base_ptr();

        {
            let mut writer = cb.writer();
            assert_eq!(writer.base_ptr(), base);
            assert_eq!(writer.get_write_ptr(), start);
            writer.add_comment("first");
            writer.add_comment("first");
            writer.write_byte(0xbb);
            writer.write_bytes(&[0xcc, 0xdd]);
            assert_eq!(writer.get_write_pos(), 4);
            assert_eq!(writer.get_write_ptr(), start.add_bytes(3));
            assert_eq!(writer.get_write_ptr().raw_addr(&writer), base.as_ptr() as usize + 4);
        }

        assert_eq!(cb.hexdump(), "aabbccdd");
        assert_eq!(cb.comments_at(start.raw_addr(&cb)).unwrap(), &["first"]);

        // A new writer can borrow memory after the previous one releases its guard.
        cb.writer().write_byte(0xee);
        assert_eq!(cb.get_write_pos(), 5);
    }

    #[test]
    fn separate_writes_cross_pages_without_losing_position_or_bytes() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let input: Vec<u8> = (0..2 * page_size + 3).map(|i| (i % 251) as u8).collect();
        let mut cb = CodeBlock::new_dummy();
        cb.writer().write_bytes(&[0xaa; 2]);

        {
            let mut writer = cb.writer();

            for (index, chunk) in input.chunks(4).enumerate() {
                if index % 2 == 0 {
                    writer.write_bytes(chunk);
                } else {
                    for &byte in chunk {
                        writer.write_byte(byte);
                    }
                }
            }

            assert_eq!(writer.get_write_pos(), 2 + input.len());
            assert!(!writer.has_dropped_bytes());

            // One preparation for the initial writer, then one per page
            // touched by this session, regardless of the number of append calls.
            assert_eq!(writer.mem.write_span_preparations(), 4);
        }

        let actual = unsafe { std::slice::from_raw_parts(cb.get_ptr(2).raw_ptr(&cb), input.len()) };
        assert_eq!(actual, input);
        assert_eq!(cb.mapped_region_size(), 3 * page_size);
    }

    #[test]
    fn slice_writes_match_bulk_at_unaligned_and_multi_page_boundaries() {
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;

        for offset in [0, 1, page_size - 1, page_size, page_size + 1] {
            for len in [0, 1, 4, page_size - 1, page_size, page_size + 1, 2 * page_size + 3] {
                let input: Vec<u8> = (0..len).map(|i| (i % 251) as u8).collect();
                let mut bulk = CodeBlock::new_dummy_sized(6 * page_size);
                let mut scoped = CodeBlock::new_dummy_sized(6 * page_size);
                bulk.set_write_ptr(bulk.get_ptr(offset));
                scoped.set_write_ptr(scoped.get_ptr(offset));

                // Exercise the independent VM bulk path, not another CodeWriter.
                let ptr = bulk.get_ptr(offset);
                bulk.mem_block.borrow_mut().write_bytes(ptr, &input).unwrap();
                bulk.write_pos += input.len();

                {
                    let mut writer = scoped.writer();

                    writer.write_bytes(&input);
                    let pages = if len == 0 { 0 } else { (offset + len - 1) / page_size - offset / page_size + 1 };
                    assert_eq!(writer.mem.write_span_preparations(), pages);
                }

                assert_eq!(scoped.get_write_pos(), offset + len);
                assert_eq!(scoped.mapped_region_size(), bulk.mapped_region_size());
                assert!(!scoped.has_dropped_bytes());

                if len > 0 {
                    // Include mapped gaps, so architecture-specific initialization
                    // must also agree, not just the bytes supplied by the caller.
                    assert_eq!(scoped.hexdump(), bulk.hexdump(), "offset={offset}, len={len}");
                }
            }
        }
    }

    #[test]
    fn early_return_commits_progress() {
        fn emit(cb: &mut CodeBlock) -> Result<(), ()> {
            let mut writer = cb.writer();
            writer.write_bytes(&[11, 22]);
            Err(())?;
            unreachable!()
        }
        let mut cb = CodeBlock::new_dummy();

        assert_eq!(emit(&mut cb), Err(()));
        assert_eq!(cb.hexdump(), "0b16");
        assert!(!cb.has_dropped_bytes());
    }

    #[test]
    fn unwinding_commits_progress_and_releases_borrow() {
        let mut cb = CodeBlock::new_dummy();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut writer = cb.writer();
            writer.write_byte(11);
            panic!("interrupt emission");
        }));

        assert!(result.is_err());
        assert_eq!(cb.hexdump(), "0b");

        cb.writer().write_byte(22);
        assert_eq!(cb.hexdump(), "0b16");
    }

    #[test]
    fn partial_failure_is_live_and_sticky_across_sessions() {
        // Allocate the input before setting the tight memory budget.
        let page_size = unsafe { crate::cruby::rb_jit_get_page_size() } as usize;
        let padding = vec![0xaa; page_size - 2];
        let (mut cb, _) = one_page_block();

        {
            let mut writer = cb.writer();

            writer.write_bytes(&padding);
            assert!(!writer.has_dropped_bytes());
            assert_eq!(writer.mem.write_span_preparations(), 1);

            writer.write_bytes(&[11, 22, 33, 44]);
            assert_eq!(writer.get_write_pos(), page_size);
            assert_eq!(writer.writable_end, page_size);
            assert!(writer.has_dropped_bytes());
            assert_eq!(writer.mem.write_span_preparations(), 2);

            writer.write_byte(55);
            assert_eq!(writer.mem.write_span_preparations(), 3);

            writer.write_bytes(&[]);
            assert_eq!(writer.mem.write_span_preparations(), 3);
            assert_eq!(writer.get_write_pos(), page_size);
        }

        assert_eq!(cb.get_write_pos(), page_size);
        assert!(cb.has_dropped_bytes());

        let prefix = cb.get_ptr(page_size - 2).raw_ptr(&cb);
        assert_eq!(unsafe { std::slice::from_raw_parts(prefix, 2) }, &[11, 22]);

        cb.set_write_ptr(cb.get_ptr(0));
        {
            let mut writer = cb.writer();
            assert!(writer.has_dropped_bytes());

            writer.write_byte(66);
            assert_eq!(writer.get_write_pos(), 1);
            assert!(writer.has_dropped_bytes());
        }

        assert_eq!(cb.hexdump(), "42");
        assert!(cb.has_dropped_bytes());
    }

    #[test]
    fn label_reservation_reports_partial_failure() {
        let (mut cb, page_size) = one_page_block();
        let label = cb.new_label("end");
        cb.set_write_ptr(cb.get_ptr(page_size - 2));

        {
            let mut writer = cb.writer();

            writer.label_ref(label, 4, |_, _, _| panic!("must not link failed emission"));
            assert_eq!(writer.get_write_pos(), page_size);
            assert!(writer.has_dropped_bytes());

            writer.write_label(label);
        }

        assert!(cb.has_dropped_bytes());
        assert_eq!(cb.resolve_label(label), cb.get_ptr(page_size));
        cb.clear_labels();
    }

    #[test]
    fn label_linking_opens_a_new_writer_after_session() {
        let mut cb = CodeBlock::new_dummy();

        let label = cb.new_label("end");

        {
            let mut writer = cb.writer();

            writer.label_ref(label, 4, |writer, end_addr, dst_addr| {
                assert_eq!((end_addr, dst_addr), (4, 5));
                writer.write_bytes(&[1, 2, 3, 4]);
                Ok(())
            });
            writer.write_byte(5);
            writer.write_label(label);
        }

        assert_eq!(cb.resolve_label(label).raw_addr(&cb), cb.base_ptr().as_ptr() as usize + 5);

        cb.link_labels().unwrap();
        assert_eq!(cb.get_write_pos(), 5);
        assert_eq!(cb.hexdump(), "0102030405");
    }

    #[test]
    fn writer_can_patch_executable_memory_inside_with_write_ptr() {
        let mut cb = CodeBlock::new_dummy();

        cb.writer().write_bytes(&[1, 2, 3, 4]);
        cb.mark_all_executable();
        let start = cb.get_ptr(1);

        let range = cb.with_write_ptr(start, |cb| {
            let mut writer = cb.writer();
            writer.write_bytes(&[8, 9]);
        });

        assert_eq!(range, start..start.add_bytes(2));
        assert_eq!(cb.get_write_pos(), 4);
        assert!(!cb.has_dropped_bytes());
        assert_eq!(cb.hexdump(), "01080904");
    }
}
