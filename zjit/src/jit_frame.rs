use crate::cruby::{IseqPtr, VALUE, rb_gc_mark_movable, rb_gc_location};
use crate::cruby::zjit_jit_frame;
use crate::state::ZJITState;

/// JITFrame struct is defined in zjit.h (the single source of truth) and
/// imported into Rust via bindgen. See zjit.h for field documentation.
pub type JITFrame = zjit_jit_frame;

impl JITFrame {
    /// Allocate a JITFrame on the heap, register it with ZJITState, and return
    /// a raw pointer that remains valid for the lifetime of the process.
    fn alloc(jit_frame: JITFrame) -> *const Self {
        let raw_ptr = Box::into_raw(Box::new(jit_frame));
        ZJITState::get_jit_frames().push(raw_ptr);
        raw_ptr as *const _
    }

    /// Create a JITFrame for an ISEQ frame.
    pub fn new_iseq(pc: *const VALUE, iseq: IseqPtr, materialize_block_code: bool) -> *const Self {
        Self::alloc(JITFrame { pc, iseq, materialize_block_code })
    }

    /// Create a JITFrame for a C frame (no PC, no ISEQ).
    pub fn new_cfunc() -> *const Self {
        Self::alloc(JITFrame { pc: std::ptr::null(), iseq: std::ptr::null(), materialize_block_code: false })
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
    use crate::cruby::{eval, inspect};
    use insta::assert_snapshot;

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
        // At the point of `resuce`, there are two lightweight frames on stack and both need to be
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

    // Side exit at the very start of a method, before any jit_return has been
    // written by gen_save_pc_for_gc. The jit_return field should be 0 (from
    // vm_push_frame), so materialization should be a no-op for that frame.
    #[test]
    fn test_side_exit_before_jit_return_write() {
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
