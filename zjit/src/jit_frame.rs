use std::alloc::{handle_alloc_error, Layout};
use std::ptr;

use crate::cast::IntoU64;
use crate::cruby::{IseqPtr, VALUE, Qnil, rb_gc_mark_movable, rb_gc_location};
use crate::cruby::{ZJIT_STACK_MAP_OP_BITS, ZJIT_STACK_MAP_VARINT_BITS, ZJIT_STACK_MAP_OP_END, ZJIT_STACK_MAP_OP_VREG, ZJIT_STACK_MAP_OP_SKIP, ZJIT_STACK_MAP_OP_BASE_PTR, ZJIT_STACK_MAP_OP_IMM, ZJIT_STACK_MAP_OP_NIL};
use crate::cruby::zjit_jit_frame;
use crate::codegen::iseq_may_write_block_code;
use crate::options::get_option;
use crate::state::ZJITState;
use crate::stats::{incr_counter_by, Counter};
use crate::virtualmem::VirtualMem;

/// JITFrame struct is defined in zjit.h (the single source of truth) and
/// imported into Rust via bindgen. See zjit.h for field documentation.
pub type JITFrame = zjit_jit_frame;

/// A bump allocator for JITFrame backed by address space below INT32_MAX.
pub struct JITFrameAllocator {
    /// Address space below `INT32_MAX`. Physical pages are mapped in on demand
    /// and, since the region is never marked executable, stay read/write for the
    /// life of the process.
    virt_mem: VirtualMem,

    /// Offset of the next free byte in `virt_mem`, or the region size once the
    /// arena is exhausted.
    cursor: usize,
}

impl JITFrameAllocator {
    /// Reserve the arena's address space, or return None when the platform cannot
    /// provide low memory.
    pub fn new() -> Option<Self> {
        // A tenth of --zjit-mem-size is reserved, not mapped: physical pages are
        // mapped in one at a time as the bump cursor crosses into them. lobsters
        // allocates up to 4MiB of JITFrames, well below the 12.8MiB default.
        Some(JITFrameAllocator {
            virt_mem: VirtualMem::alloc_low(get_option!(mem_bytes) / 10)?,
            cursor: 0,
        })
    }

    /// The number of bytes the allocator has mapped physical memory for.
    pub fn mapped_bytes(&self) -> usize {
        self.virt_mem.mapped_region_size()
    }

    /// Bump-allocate `layout` from the arena, or return null when it's full.
    fn try_alloc(&mut self, layout: Layout) -> *mut u8 {
        // The region start is page-aligned, so aligning the offset aligns the pointer.
        debug_assert!(layout.align() <= self.virt_mem.system_page_size());
        let start = self.cursor.next_multiple_of(layout.align());
        let Some(end) = start.checked_add(layout.size()) else {
            return ptr::null_mut();
        };
        if end > self.virt_mem.virtual_region_size() {
            return ptr::null_mut();
        }
        // Touch the last byte of the allocation on first use: write_byte maps every
        // page between the end of the mapped region and the byte it writes.
        if end > self.virt_mem.mapped_region_size() {
            let last_byte = self.virt_mem.start_ptr().add_bytes(end - 1);
            if self.virt_mem.write_byte(last_byte, 0).is_err() {
                // write_byte's bound check refuses the final page of the region, so
                // treat any failure as permanent exhaustion instead of retrying on
                // every allocation.
                self.cursor = self.virt_mem.virtual_region_size();
                return ptr::null_mut();
            }
        }
        self.cursor = end;
        self.virt_mem.start_ptr().add_bytes(start).raw_ptr(&self.virt_mem) as *mut u8
    }
}

/// Bump-allocate `layout` from the JITFrame arena, falling back to the heap.
fn alloc_jit_frame_memory(layout: Layout) -> *mut u8 {
    // Prefer the low-address arena so that call sites can store JITFrame pointers
    // as a 32-bit immediate. Falling back to the heap only costs code size.
    let mut raw_ptr = match ZJITState::get_jit_frame_allocator() {
        Some(arena) => arena.try_alloc(layout),
        None => ptr::null_mut(),
    };
    if raw_ptr.is_null() {
        raw_ptr = unsafe { std::alloc::alloc(layout) };
        if raw_ptr.is_null() {
            handle_alloc_error(layout);
        }
        incr_counter_by(Counter::jit_frame_heap_bytes, layout.size().as_u64());
    }
    raw_ptr
}

/// Stack maps with no entries, indexed by materialize_block_code.
/// Bit 0 is the flag and the END opcode that follows is all zeros.
static EMPTY_STACK_MAPS: [u8; 2] = [0, 1];
const _: () = assert!(ZJIT_STACK_MAP_OP_END == 0);

/// Writes a JITFrame stack map bit stream. The bit stream is little endian.
/// Bit 0 is `materialize_block_code`.
/// The rest is `opcode, payload` pairs on repeat where:
///   - `opcode` is [`ZJIT_STACK_MAP_OP_BITS`] bits wide.
///   - `payload` is 0 or more variable width integer ("varint") chunks, depending on the opcode.
///   - Each varint chunk is [`ZJIT_STACK_MAP_VARINT_BITS`] plus one continuation bit. The varint
///     ends when the continuation bit is clear. The width upper bound of varint is the number of
///     bits in a `VALUE`.
/// The opcode [`ZJIT_STACK_MAP_OP_END`] has no payload and ends the stream.
///
/// zjit_materialize_frames() decodes the opcodes in order while moving a write cursor down the VM
/// stack.
pub struct StackMapWriter {
    bytes: Vec<u8>,
    num_bits: usize,
}

#[cfg(test)]
#[test]
fn test_bit_stream_example() {
    let mut writer = StackMapWriter::new(true);
    writer.vreg(5);  // one varint chunk
    writer.skip(17); // two varint chunks
    // Fields are packed LSB first, so the literal reads right to left from bit 0. In each varint
    // chunk the continuation bit sits above the 4 payload bits, so 17 is lo=1_0001 then hi=0_0001.
    //                  END 17(hi) 17(lo) SKIP 5      VREG materialize_block_code
    let stream: u32 = 0b000_0_0001_1_0001_010__0_0101_001__1;
    assert_eq!(writer.finish(), stream.to_le_bytes());
}

impl StackMapWriter {
    pub fn new(materialize_block_code: bool) -> Self {
        let mut writer = Self { bytes: vec![], num_bits: 0 };
        writer.write_bits(u64::from(materialize_block_code), 1);
        writer
    }

    fn write_bits(&mut self, value: u64, num_bits: u32) {
        for i in 0..num_bits {
            if self.num_bits % 8 == 0 {
                self.bytes.push(0);
            }
            *self.bytes.last_mut().unwrap() |= (((value >> i) & 1) as u8) << (self.num_bits % 8);
            self.num_bits += 1;
        }
    }

    fn write_op(&mut self, op: u32) {
        debug_assert!(op < 1 << ZJIT_STACK_MAP_OP_BITS);
        self.write_bits(op.into(), ZJIT_STACK_MAP_OP_BITS);
    }

    fn write_varint(&mut self, mut value: u64) {
        let payload_mask = (1 << ZJIT_STACK_MAP_VARINT_BITS) - 1;
        loop {
            let chunk = value & payload_mask;
            value >>= ZJIT_STACK_MAP_VARINT_BITS;
            let cont_bit = u64::from(value != 0);
            self.write_bits(chunk | cont_bit << ZJIT_STACK_MAP_VARINT_BITS, ZJIT_STACK_MAP_VARINT_BITS + 1);
            if cont_bit == 0 {
                break;
            }
        }
    }

    /// ZJIT_STACK_MAP_OP_VREG. Operand: slot index below `cfp->jit_return`.
    /// Writes `jit_return[-slot_index]`.
    pub fn vreg(&mut self, slot_index: usize) {
        self.write_op(ZJIT_STACK_MAP_OP_VREG);
        self.write_varint(slot_index.as_u64());
    }

    /// ZJIT_STACK_MAP_OP_NIL writes Qnil. Other immediates use
    /// ZJIT_STACK_MAP_OP_IMM, whose operand is the VALUE to write.
    pub fn imm(&mut self, value: VALUE) {
        assert!(value.special_const_p(), "StackMap should only materialize immediate VALUEs, but got: {value:?}");
        if value == Qnil {
            self.write_op(ZJIT_STACK_MAP_OP_NIL);
        } else {
            self.write_op(ZJIT_STACK_MAP_OP_IMM);
            self.write_varint(value.as_u64());
        }
    }

    /// ZJIT_STACK_MAP_OP_SKIP. Operand: number of slots to move the cursor down
    /// without writing.
    pub fn skip(&mut self, size: usize) {
        self.write_op(ZJIT_STACK_MAP_OP_SKIP);
        self.write_varint(size.as_u64());
    }

    /// ZJIT_STACK_MAP_OP_BASE_PTR. Operands: slot index, stack size. Anchors the
    /// cursor at `((VALUE **)cfp->jit_return)[-slot_index] + stack_size`, i.e. on
    /// the SP register the JIT saved on its native stack instead of on `cfp->sp`.
    /// `cfp->sp` is not a reliable starting point for a frame that is in the
    /// middle of a non-leaf C call, as e.g. raising ArgumentError can push through
    /// and move `cfp->sp`, then use the stack map. gen_prepare_non_leaf_call()
    /// emits this opcode, always as the first one, so the opcodes after decode to
    /// the right place.
    pub fn base_ptr(&mut self, slot_index: u32, stack_size: u32) {
        debug_assert_eq!(self.num_bits, 1, "base_ptr must be the first StackMap entry so later entries decode from it");
        self.write_op(ZJIT_STACK_MAP_OP_BASE_PTR);
        self.write_varint(slot_index.into());
        self.write_varint(stack_size.into());
    }

    /// Terminate the stream with ZJIT_STACK_MAP_OP_END and return its bytes.
    pub fn finish(mut self) -> Vec<u8> {
        self.write_op(ZJIT_STACK_MAP_OP_END);
        self.bytes
    }
}

impl JITFrame {
    /// Allocate a JITFrame with an empty stack map, register it with ZJITState,
    /// and return a raw pointer that remains valid for the lifetime of the process.
    fn alloc(pc: *const VALUE, iseq: IseqPtr, materialize_block_code: bool) -> *const Self {
        let raw_ptr: *mut Self = alloc_jit_frame_memory(Layout::new::<JITFrame>()).cast();
        unsafe {
            ptr::write(raw_ptr, JITFrame {
                pc,
                iseq,
                stack_map: &EMPTY_STACK_MAPS[usize::from(materialize_block_code)],
            });
        }
        ZJITState::get_jit_frames().push(raw_ptr);
        raw_ptr.cast_const()
    }

    pub fn materialize_block_code(&self) -> bool {
        // The 0th bit of the bitstream is this boolean.
        let zeroth_byte = unsafe { *self.stack_map };
        zeroth_byte & 1 != 0
    }

    pub fn stack_map_writer(&self) -> StackMapWriter {
        StackMapWriter::new(self.materialize_block_code())
    }

    /// Install a stack map built from [Self::stack_map_writer].
    pub fn set_stack_map(&mut self, writer: StackMapWriter) {
        debug_assert_eq!(writer.bytes.first().map(|byte| byte & 1 != 0), Some(self.materialize_block_code()));
        // Avoid allocating memory more than once for the same stack map
        if EMPTY_STACK_MAPS.iter().all(|empty| !ptr::eq(self.stack_map, empty)) {
            return;
        }
        let bytes = writer.finish();
        let stack_map = alloc_jit_frame_memory(Layout::array::<u8>(bytes.len()).unwrap());
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), stack_map, bytes.len()); }
        incr_counter_by(Counter::jit_frame_stack_map_bytes, bytes.len().as_u64());
        self.stack_map = stack_map;
    }

    /// Create a JITFrame for an ISEQ frame.
    pub fn new_iseq(pc: *const VALUE, iseq: IseqPtr) -> *const Self {
        let materialize_block_code = !iseq_may_write_block_code(iseq);
        Self::alloc(pc, iseq, materialize_block_code)
    }

    /// Mark the iseq pointer for GC. Called from rb_zjit_root_mark.
    pub fn mark(&self) {
        if !self.iseq.is_null() {
            unsafe { rb_gc_mark_movable(VALUE::from(self.iseq)); }
        }
    }

    /// Update the iseq pointer after GC compaction.
    pub fn update_references(&mut self) {
        if !self.iseq.is_null() {
            let new_iseq = unsafe { rb_gc_location(VALUE::from(self.iseq)) }.as_iseq();
            if self.iseq != new_iseq {
                self.iseq = new_iseq;
            }
        }
    }
}

/// Update the iseq pointer in an on-stack JITFrame during GC compaction.
/// Called from rb_execution_context_update in vm.c.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_frame_update_references(jit_frame: *mut JITFrame) {
    unsafe { &mut *jit_frame }.update_references();
}

#[cfg(test)]
mod tests {
    use crate::cruby::{eval, inspect, VALUE};
    use insta::assert_snapshot;
    use super::StackMapWriter;

    #[test]
    fn test_stack_map_writer_bit_layout() {
        let mut writer = StackMapWriter::new(true);
        writer.vreg(5);
        writer.imm(VALUE::fixnum_from_isize(-1)); // all 64 bits set, so 16 varint chunks
        writer.skip(17); // two varint chunks
        // Fields are packed LSB first, so each byte reads right to left. A varint
        // chunk is 4 payload bits followed by a continuation bit, so 17 is chunks
        // lo=1 and hi=1, and -1 is 15 chunks of 1111 with cont=1, then 1111 with cont=0.
        assert_eq!(writer.finish(), vec![
            0b0101_001_1,   // 5 payload=0101 | VREG=001       | flag=1
            0b1111_100_0,   // -1 chunk 0     | IMM=100        | 5 cont=0
            0b11111111,     // -1 chunk 0 cont through chunk 15 payload[0], all ones
            0b11111111,
            0b11111111,
            0b11111111,
            0b11111111,
            0b11111111,
            0b11111111,
            0b11111111,
            0b11111111,
            0b1_010_0_111,  // 17 lo[0]=1     | SKIP=010       | -1 chunk 15 cont=0 | -1 chunk 15 payload[3:1]=111
            0b0001_1_000,   // 17 hi=0001     | 17 lo cont=1   | 17 lo[3:1]=000
            0b0000_000_0,   // padding=0000   | END=000        | 17 hi cont=0
        ]);
    }

    #[test]
    fn test_jit_frame_entry_first() {
        eval(r#"
            def test
              itself
              callee
            end

            def callee
              caller
            end

            test
        "#);
        assert_snapshot!(inspect("test.first"), @r#""<compiled>:4:in 'Object#test'""#);
    }

    #[test]
    fn test_materialize_one_frame() {
        assert_snapshot!(inspect("
            def jit_entry
              raise rescue 1
            end
            jit_entry
            jit_entry
        "), @"1");
    }

    #[test]
    fn test_materialize_two_frames() { // materialize caller frames on raise
        // At the point of `rescue`, there are two inline frames on stack and both need to be
        // materialized before passing control to interpreter.
        assert_snapshot!(inspect("
            def jit_entry = raise_and_rescue
            def raise_and_rescue
              raise rescue 1
            end
            jit_entry
            jit_entry
        "), @"1");
    }

    // Direct JIT-to-JIT entry passes callee locals as native arguments. If the
    // callee ISEQ has already escaped EP, later getlocal reads use EP memory,
    // so JIT entry must materialize those locals into the callee frame.
    #[test]
    fn test_jit_entry_materializes_ep_escaped_locals() {
        assert_snapshot!(inspect("
            def poison(*) = nil

            def victim(a, b, c)
              lambda { a }
              a
            end

            def jit_entry
              poison([], [], [], [])
              victim(:expected, 1, 2)
            end

            jit_entry
            Array.new(100) { jit_entry }.uniq
        "), @"[:expected]");
    }

    // Materialize frames on side exit: a type guard triggers a side exit with
    // multiple JIT frames on the stack. All frames must be materialized before
    // the interpreter resumes.
    #[test]
    fn test_side_exit_materialize_frames() {
        assert_snapshot!(inspect("
            def side_exit(n) = 1 + n
            def jit_frame(n) = 1 + side_exit(n)
            def entry(n) = jit_frame(n)
            entry(2)
            [entry(2), entry(2.0)]
        "), @"[4, 4.0]");
    }

    // BOP invalidation must not overwrite the top-most frame's PC with
    // jit_frame's PC. After invalidation the interpreter resumes at a new
    // PC, so a stale jit_frame PC would cause wrong execution.
    #[test]
    fn test_bop_invalidation() {
        assert_snapshot!(inspect(r#"
            def test
              eval("class Integer; def +(_) = 100; end")
              1 + 2
            end
            test
            test
        "#), @"100");
    }

    // Side exit at the very start of a method, before gen_save_pc_for_gc has
    // updated the entry JITFrame.
    #[test]
    fn test_side_exit_before_jit_frame_update() {
        assert_snapshot!(inspect("
            def entry(n) = n + 1
            entry(1)
            [entry(1), entry(1.0)]
        "), @"[2, 2.0]");
    }

    #[test]
    fn test_caller_iseq() {
        assert_snapshot!(inspect(r#"
            def callee = call_caller
            def test = callee

            def callee2 = call_caller
            def test2 = callee2

            def call_caller = caller

            test
            test2
            test.first
        "#), @r#""<compiled>:2:in 'Object#callee'""#);
    }

    // ISEQ must be readable during exception handling so the interpreter
    // can look up rescue/ensure tables.
    #[test]
    fn test_iseq_on_raise() {
        assert_snapshot!(inspect(r#"
            def jit_entry(v) = make_range_then_exit(v)
            def make_range_then_exit(v)
              range = (v..1)
              super rescue range
            end
            jit_entry(0)
            jit_entry(0)
            jit_entry(0/1r)
        "#), @"(0/1)..1");
    }

    // Multiple exception raises during keyword argument evaluation: each
    // raise needs correct ISEQ for catch table lookup.
    #[test]
    fn test_iseq_on_raise_on_ensure() {
        assert_snapshot!(inspect(r#"
            def raise_a = raise "a"
            def raise_b = raise "b"
            def raise_c = raise "c"

            def foo(a: raise_a, b: raise_b, c: raise_c)
              [a, b, c]
            end

            def test_a
              foo(b: 2, c: 3)
            rescue RuntimeError => e
              e.message
            end

            def test_b
              foo(a: 1, c: 3)
            rescue RuntimeError => e
              e.message
            end

            def test_c
              foo(a: 1, b: 2)
            rescue RuntimeError => e
              e.message
            end

            def test
              [test_a, test_b, test_c]
            end

            test
            test
        "#), @r#"["a", "b", "c"]"#);
    }

    // Send fallback (e.g. method_missing) calls into the interpreter, which
    // reads cfp->iseq via GET_ISEQ(). gen_prepare_non_leaf_call writes the
    // iseq to JITFrame, but GET_ISEQ reads cfp->iseq directly. This test
    // ensures the interpreter can resolve the caller iseq for backtraces.
    #[test]
    fn test_send_fallback_caller_location() {
        assert_snapshot!(inspect(r#"
            def callee = caller_locations(1, 1)[0].label
            def test = callee
            test
            test
        "#), @r#""Object#test""#);
    }

    // A send fallback may throw (e.g. via method_missing raising). The
    // interpreter must be able to find the correct rescue handler in the
    // caller's ISEQ catch table. This exercises throw through send fallback.
    #[test]
    fn test_send_fallback_throw() {
        assert_snapshot!(inspect(r#"
            class Foo
              def method_missing(name, *) = raise("no #{name}")
            end
            def test
              Foo.new.bar
            rescue RuntimeError => e
              e.message
            end
            test
            test
        "#), @r#""no bar""#);
    }

    // This test makes a JIT control frame move cfp->sp from as set by gen_prepare_non_leaf_call()
    // and then ask for materialization. A C function that calls back into Ruby (rb_const_missing
    // here) pushes recv+args using jit_entry's cfp->sp via vm_call0_body(). A wrong arity makes
    // vm_callee_setup_arg() raise before vm_call_iseq_setup_normal() restores cfp->sp, so cfp->sp
    // is left 1+argc slots high while this frame is materialized for the rescue. At the time of
    // materialization, the top most control frame is the JIT frame.
    #[test]
    fn test_stack_map_anchor_after_callee_arity_error() {
        assert_snapshot!(inspect(r#"
            class Holder
              def self.const_missing(a, b) = nil # wrong arity: called with 1 arg
            end
            def jit_entry
              [1, (begin # the 1 is live across the const_missing call
                     Holder::NOPE
                   rescue ArgumentError
                     2
                   end)]
            end
            jit_entry
            jit_entry
        "#), @"[1, 2]");
    }

    // Same displaced cfp->sp, but reaching across an inlined frame: `defined?`
    // calls respond_to_missing? with 2 args, which raises on arity.
    #[test]
    fn test_stack_map_anchor_with_inlined_frame() {
        assert_snapshot!(inspect(r#"
            class BadResponder
              def respond_to_missing?(name) = true # wrong arity: called with 2
            end
            class Test
              def initialize = @o = BadResponder.new
              def inner = defined?(@o.nope) # must have 0 locals
              def outer = [1, inner] # the 1 is live across the inlined call
            end
            test = Test.new
            test.outer
            test.outer
        "#), @"[1, nil]");
    }

    // Proc.new inside a block passed via invokeblock captures the caller's
    // block_code. When the JIT compiles the caller, block_code must be
    // correctly available for the proc to work.
    #[test]
    fn test_proc_from_invokeblock() {
        assert_snapshot!(inspect("
            def capture_block(&blk) = blk
            def test = capture_block { 42 }
            test
            test.call
        "), @"42");
    }

    // binding() called from a JIT-compiled callee must see the correct
    // source location (iseq + pc) of the caller frame.
    #[test]
    fn test_binding_source_location() {
        assert_snapshot!(inspect(r#"
            def callee = binding
            def test = callee
            test
            b = test
            b.source_location[1] > 0
        "#), @"true");
    }

    // $~ (Regexp special variable) is stored via svar which walks the EP
    // chain to find the LEP. rb_vm_svar_lep uses rb_zjit_cfp_has_iseq to
    // skip C frames, so it must work correctly with JITFrame.
    #[test]
    fn test_svar_regexp_match() {
        assert_snapshot!(inspect(r#"
            def test(s)
              s =~ /hello/
              $~
            end
            test("hello world")
            test("hello world").to_s
        "#), @r#""hello""#);
    }

    // C function calls with rb_block_call (like Array#each, Enumerable#map)
    // write an ifunc to cfp->block_code after the JIT pushes the C frame.
    // GC must mark and relocate this ifunc. This test exercises the code
    // path fixed by "Fix ZJIT segfault: write block_code for C frames and
    // fix GC marking".
    #[test]
    fn test_cfunc_block_code_gc() {
        assert_snapshot!(inspect("
            def test
              # Use a cfunc that calls back into Ruby with a block (rb_block_call)
              [1, 2, 3].map { |x| x.to_s }
            end
            test
            test
        "), @r#"["1", "2", "3"]"#);
    }

    // Multiple levels of cfunc-with-block: a JIT-compiled method calls a
    // cfunc that yields, and the block itself calls another cfunc that
    // yields. Each C frame's block_code must be properly initialized.
    #[test]
    fn test_nested_cfunc_with_block() {
        assert_snapshot!(inspect("
            def test
              [1, 2].flat_map { |x| [x, x + 10].map { |y| y * 2 } }
            end
            test
            test
        "), @"[2, 22, 4, 24]");
    }
}
