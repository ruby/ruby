use crate::cruby::{IseqPtr, VALUE};

#[derive(Debug)]
pub struct JITFrame {
    pub pc: *const VALUE,
    pub iseq: IseqPtr, // TODO: mark this
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_pc(jit_return: *const JITFrame) -> *const VALUE {
    unsafe { (*jit_return).pc }
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_jit_return_iseq(jit_return: *const JITFrame) -> IseqPtr {
    unsafe { (*jit_return).iseq }
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
        "#), @r#""#);
    }
}
