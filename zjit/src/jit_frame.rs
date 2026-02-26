use crate::cruby::{IseqPtr, VALUE};

// TODO: consider making it C ABI compatible and let C function read it directly
// instead of calling a Rust function
#[derive(Debug)]
pub struct JITFrame {
    pub pc: *const VALUE,
    pub iseq: IseqPtr, // marked in rb_execution_context_mark
    pub materialize_block_code: bool,
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_pc(jit_return: *const JITFrame) -> *const VALUE {
    unsafe { (*jit_return).pc }
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_iseq(jit_return: *const JITFrame) -> IseqPtr {
    unsafe { (*jit_return).iseq }
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_set_iseq(jit_return: *mut JITFrame, iseq: IseqPtr) {
    unsafe { (*jit_return).iseq = iseq; }
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_materialize_block_code(jit_return: *const JITFrame) -> bool {
    unsafe { (*jit_return).materialize_block_code }
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

    // TODO: minimize (materialize frames on side exit)
    #[test]
    fn test_opt_plus_type_guard_nested_exit() {
        assert_snapshot!(inspect("
            def side_exit(n) = 1 + n
            def jit_frame(n) = 1 + side_exit(n)
            def entry(n) = jit_frame(n)
            entry(2) # profile send
            [entry(2), entry(2.0)]
        "), @"[4, 4.0]");
    }

    // TODO: minimize: do not overwrite the top-most frame's PC with jit_frame's PC on invalidation exit
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

    // TODO: write a test with side exit before writing any jit_return (uninitialized jit_return as of side exit)

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

    #[test]
    fn test_iseq_on_raise() { // TODO: minimize
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

    #[test]
    fn test_iseq_on_raise_on_ensure() { // TODO: minimize
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

    // TODO: write a test case for GET_ISEQ references in send fallbacks

    // TODO: write a test case for GET_ISEQ references in throw from send fallbacks

    // TODO: write a test case for escaping proc from invokeblock fallback

    // TODO: write a test case for rb_vm_get_sourceline from rb_f_binding

    // TODO: write a test case for svar (iseq reference on rb_vm_svar_lep)
}
