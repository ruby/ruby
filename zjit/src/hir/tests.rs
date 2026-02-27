#[cfg(test)]
use super::*;

#[cfg(test)]
mod snapshot_tests {
    use super::*;
    use insta::assert_snapshot;

    #[track_caller]
    fn hir_string(method: &str) -> String {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let function = iseq_to_hir(iseq).unwrap();
        format!("{}", FunctionPrinter::with_snapshot(&function))
    }

    #[track_caller]
    fn optimized_hir_string(method: &str) -> String {
        let iseq = crate::cruby::with_rubyvm(|| get_proc_iseq(&format!("{}.method(:{})", "self", method)));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let mut function = iseq_to_hir(iseq).unwrap();
        function.optimize();
        function.validate().unwrap();
        format!("{}", FunctionPrinter::with_snapshot(&function))
    }

    #[test]
    fn test_remove_redundant_patch_points() {
        eval("
            def test = 1 + 2 + 3
            test
            test
        ");
        assert_snapshot!(optimized_hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          Entries bb1, bb2
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [], locals: [] }
          PatchPoint NoTracePoint
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          v13:Any = Snapshot FrameState { pc: 0x1008, stack: [v10, v12], locals: [] }
          PatchPoint MethodRedefined(Integer@0x1010, +@0x1018, cme:0x1020)
          IncrCounter inline_cfunc_optimized_send_count
          v35:Fixnum[6] = Const Value(6)
          IncrCounter inline_cfunc_optimized_send_count
          v21:Any = Snapshot FrameState { pc: 0x1048, stack: [v35], locals: [] }
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_new_array_with_elements() {
        eval("def test(a, b) = [a, b]");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb0():
          Entries bb1, bb2
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v14:Any = Snapshot FrameState { pc: 0x1008, stack: [], locals: [a=v12, b=v13] }
          v15:Any = Snapshot FrameState { pc: 0x1010, stack: [], locals: [a=v12, b=v13] }
          PatchPoint NoTracePoint
          v17:Any = Snapshot FrameState { pc: 0x1018, stack: [v12], locals: [a=v12, b=v13] }
          v18:Any = Snapshot FrameState { pc: 0x1020, stack: [v12, v13], locals: [a=v12, b=v13] }
          v19:ArrayExact = NewArray v12, v13
          v20:Any = Snapshot FrameState { pc: 0x1028, stack: [v19], locals: [a=v12, b=v13] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_send_direct_with_reordered_kwargs_has_snapshot() {
        eval("
            def foo(a:, b:, c:) = [a, b, c]
            def test = foo(c: 3, a: 1, b: 2)
            test
            test
        ");
        assert_snapshot!(optimized_hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          Entries bb1, bb2
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [], locals: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[1] = Const Value(1)
          v15:Fixnum[2] = Const Value(2)
          v16:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13, v15], locals: [] }
          v23:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v13, v15, v11], locals: [] }
          PatchPoint NoSingletonClass(Object@0x1010)
          PatchPoint MethodRedefined(Object@0x1010, foo@0x1018, cme:0x1020)
          v26:HeapObject[class_exact*:Object@VALUE(0x1010)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1010)]
          v27:BasicObject = SendDirect v26, 0x1048, :foo (0x1058), v13, v15, v11
          v18:Any = Snapshot FrameState { pc: 0x1060, stack: [v27], locals: [] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_send_direct_with_kwargs_in_order_has_snapshot() {
        eval("
            def foo(a:, b:) = [a, b]
            def test = foo(a: 1, b: 2)
            test
            test
        ");
        assert_snapshot!(optimized_hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          Entries bb1, bb2
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [], locals: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          v14:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13], locals: [] }
          PatchPoint NoSingletonClass(Object@0x1010)
          PatchPoint MethodRedefined(Object@0x1010, foo@0x1018, cme:0x1020)
          v23:HeapObject[class_exact*:Object@VALUE(0x1010)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1010)]
          v24:BasicObject = SendDirect v23, 0x1048, :foo (0x1058), v11, v13
          v16:Any = Snapshot FrameState { pc: 0x1060, stack: [v24], locals: [] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_send_direct_with_many_kwargs_no_reorder_snapshot() {
        eval("
            def foo(five, six, a:, b:, c:, d:, e:, f:) = [a, b, c, d, five, six, e, f]
            def test = foo(5, 6, d: 4, c: 3, a: 1, b: 2, e: 7, f: 8)
            test
            test
        ");
        assert_snapshot!(optimized_hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          Entries bb1, bb2
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [], locals: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[5] = Const Value(5)
          v13:Fixnum[6] = Const Value(6)
          v15:Fixnum[4] = Const Value(4)
          v17:Fixnum[3] = Const Value(3)
          v19:Fixnum[1] = Const Value(1)
          v21:Fixnum[2] = Const Value(2)
          v23:Fixnum[7] = Const Value(7)
          v25:Fixnum[8] = Const Value(8)
          v26:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13, v15, v17, v19, v21, v23, v25], locals: [] }
          v27:BasicObject = Send v6, :foo, v11, v13, v15, v17, v19, v21, v23, v25 # SendFallbackReason: Too many arguments for LIR
          v28:Any = Snapshot FrameState { pc: 0x1010, stack: [v27], locals: [] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v27
        ");
    }
}

#[cfg(test)]
pub mod hir_build_tests {
    use super::*;
    use crate::options::set_call_threshold;
    use insta::assert_snapshot;

    fn iseq_contains_opcode(iseq: IseqPtr, expected_opcode: u32) -> bool {
        let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
        let mut insn_idx = 0;
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            if opcode == expected_opcode {
                return true;
            }
            insn_idx += insn_len(opcode as usize);
        }
        false
    }

    #[track_caller]
    pub fn assert_contains_opcode(method: &str, opcode: u32) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        assert!(iseq_contains_opcode(iseq, opcode), "iseq {method} does not contain {}", insn_name(opcode as usize));
    }

    #[track_caller]
    fn assert_contains_opcodes(method: &str, opcodes: &[u32]) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        for &opcode in opcodes {
            assert!(iseq_contains_opcode(iseq, opcode), "iseq {method} does not contain {}", insn_name(opcode as usize));
        }
    }

    /// Combine multiple hir_string() results to match all of them at once, which allows
    /// us to avoid running the set of zjit-test -> zjit-test-update multiple times.
    #[macro_export]
    macro_rules! hir_strings {
        ($( $s:expr ),+ $(,)?) => {{
            vec![$( hir_string($s) ),+].join("\n")
        }};
    }

    #[track_caller]
    fn hir_string(method: &str) -> String {
        hir_string_proc(&format!("{}.method(:{})", "self", method))
    }

    #[track_caller]
    fn hir_string_proc(proc: &str) -> String {
        let iseq = crate::cruby::with_rubyvm(|| get_proc_iseq(proc));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let function = iseq_to_hir(iseq).unwrap();
        hir_string_function(&function)
    }

    #[track_caller]
    fn hir_string_function(function: &Function) -> String {
        format!("{}", FunctionPrinter::without_snapshot(function))
    }

    #[track_caller]
    fn assert_compile_fails(method: &str, reason: ParseError) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let result = iseq_to_hir(iseq);
        assert!(result.is_err(), "Expected an error but successfully compiled to HIR: {}", FunctionPrinter::without_snapshot(&result.unwrap()));
        assert_eq!(result.unwrap_err(), reason);
    }

    #[test]
    fn test_compile_optional() {
        eval("def test(x=1) = 123");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:CPtr = LoadPC
          v5:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v6:CBool = IsBitEqual v4, v5
          IfTrue v6, bb3(v1, v3)
          Jump bb5(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:NilClass = Const Value(nil)
          Jump bb3(v10, v11)
        bb3(v17:BasicObject, v18:BasicObject):
          v21:Fixnum[1] = Const Value(1)
          Jump bb5(v17, v21)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :x@1
          Jump bb5(v14, v15)
        bb5(v24:BasicObject, v25:BasicObject):
          v29:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_putobject() {
        eval("def test = 123");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_new_array() {
        eval("def test = []");
        assert_contains_opcode("test", YARVINSN_newarray);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:ArrayExact = NewArray
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_new_array_with_element() {
        eval("def test(a) = [a]");
        assert_contains_opcode("test", YARVINSN_newarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:ArrayExact = NewArray v10
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_new_array_with_elements() {
        eval("def test(a, b) = [a, b]");
        assert_contains_opcode("test", YARVINSN_newarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:ArrayExact = NewArray v12, v13
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_new_range_inclusive_with_one_element() {
        eval("def test(a) = (a..10)");
        assert_contains_opcode("test", YARVINSN_newrange);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[10] = Const Value(10)
          v17:RangeExact = NewRange v10 NewRangeInclusive v15
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_new_range_inclusive_with_two_elements() {
        eval("def test(a, b) = (a..b)");
        assert_contains_opcode("test", YARVINSN_newrange);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:RangeExact = NewRange v12 NewRangeInclusive v13
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_new_range_exclusive_with_one_element() {
        eval("def test(a) = (a...10)");
        assert_contains_opcode("test", YARVINSN_newrange);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[10] = Const Value(10)
          v17:RangeExact = NewRange v10 NewRangeExclusive v15
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_new_range_exclusive_with_two_elements() {
        eval("def test(a, b) = (a...b)");
        assert_contains_opcode("test", YARVINSN_newrange);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:RangeExact = NewRange v12 NewRangeExclusive v13
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_array_dup() {
        eval("def test = [1, 2, 3]");
        assert_contains_opcode("test", YARVINSN_duparray);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:ArrayExact = ArrayDup v10
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_hash_dup() {
        eval("def test = {a: 1, b: 2}");
        assert_contains_opcode("test", YARVINSN_duphash);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:HashExact = HashDup v10
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_new_hash_empty() {
        eval("def test = {}");
        assert_contains_opcode("test", YARVINSN_newhash);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:HashExact = NewHash
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_new_hash_with_elements() {
        eval("def test(aval, bval) = {a: aval, b: bval}");
        assert_contains_opcode("test", YARVINSN_newhash);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :aval@0x1000
          v4:BasicObject = LoadField v2, :bval@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :aval@1
          v9:BasicObject = LoadArg :bval@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v17:StaticSymbol[:a] = Const Value(VALUE(0x1008))
          v20:StaticSymbol[:b] = Const Value(VALUE(0x1010))
          v23:HashExact = NewHash v17: v12, v20: v13
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_string_copy() {
        eval("def test = \"hello\"");
        assert_contains_opcode("test", YARVINSN_putchilledstring);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_bignum() {
        eval("def test = 999999999999999999999999999999999999");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Bignum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_flonum() {
        eval("def test = 1.5");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Flonum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_heap_float() {
        eval("def test = 1.7976931348623157e+308");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:HeapFloat[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_static_sym() {
        eval("def test = :foo");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_opt_plus() {
        eval("def test = 1+2");
        assert_contains_opcode("test", YARVINSN_opt_plus);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          v15:BasicObject = Send v10, :+, v12 # SendFallbackReason: Uncategorized(opt_plus)
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_opt_hash_freeze() {
        eval("
            def test = {}.freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_hash_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_hash_freeze_rewritten() {
        eval("
            class Hash
              def freeze; 5; end
            end
            def test = {}.freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_hash_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          SideExit PatchPoint(BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE))
        ");
    }

    #[test]
    fn test_opt_ary_freeze() {
        eval("
            def test = [].freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_ary_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_ary_freeze_rewritten() {
        eval("
            class Array
              def freeze; 5; end
            end
            def test = [].freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_ary_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE))
        ");
    }

    #[test]
    fn test_opt_str_freeze() {
        eval("
            def test = ''.freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_str_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_str_freeze_rewritten() {
        eval("
            class String
              def freeze; 5; end
            end
            def test = ''.freeze
        ");
        assert_contains_opcode("test", YARVINSN_opt_str_freeze);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          SideExit PatchPoint(BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE))
        ");
    }

    #[test]
    fn test_opt_str_uminus() {
        eval("
            def test = -''
        ");
        assert_contains_opcode("test", YARVINSN_opt_str_uminus);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_str_uminus_rewritten() {
        eval("
            class String
              def -@; 5; end
            end
            def test = -''
        ");
        assert_contains_opcode("test", YARVINSN_opt_str_uminus);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          SideExit PatchPoint(BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS))
        ");
    }

    #[test]
    fn test_setlocal_getlocal() {
        eval("
            def test
              a = 1
              a
            end
        ");
        assert_contains_opcodes("test", &[YARVINSN_getlocal_WC_0, YARVINSN_setlocal_WC_0]);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:BasicObject, v9:NilClass):
          v13:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_nested_setlocal_getlocal() {
        eval("
          l3 = 3
          _unused = _unused1 = nil
          1.times do |l2|
            _ = nil
            l2 = 2
            1.times do |l1|
              l1 = 1
              define_method(:test) do
                l1 = l2
                l2 = l1 + l2
                l3 = l2 + l3
              end
            end
          end
        ");
        assert_contains_opcodes(
            "test",
            &[YARVINSN_getlocal_WC_1, YARVINSN_setlocal_WC_1,
              YARVINSN_getlocal, YARVINSN_setlocal]);
        assert_snapshot!(hir_string("test"), @r"
        fn block (3 levels) in <compiled>@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:CPtr = GetEP 2
          v11:BasicObject = LoadField v10, :l2@0x1000
          SetLocal :l1, l1, EP@3, v11
          v16:CPtr = GetEP 1
          v17:BasicObject = LoadField v16, :l1@0x1001
          v19:CPtr = GetEP 2
          v20:BasicObject = LoadField v19, :l2@0x1000
          v23:BasicObject = Send v17, :+, v20 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :l2, l2, EP@4, v23
          v28:CPtr = GetEP 2
          v29:BasicObject = LoadField v28, :l2@0x1000
          v31:CPtr = GetEP 3
          v32:BasicObject = LoadField v31, :l3@0x1002
          v35:BasicObject = Send v29, :+, v32 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :l3, l3, EP@5, v35
          CheckInterrupts
          Return v35
        "
        );
    }

    #[test]
    fn test_setlocal_in_default_args() {
        eval("
            def test(a = (b = 1)) = [a, b]
        ");
        assert_contains_opcode("test", YARVINSN_setlocal_WC_0);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:NilClass = Const Value(nil)
          v5:CPtr = LoadPC
          v6:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v7:CBool = IsBitEqual v5, v6
          IfTrue v7, bb3(v1, v3, v4)
          Jump bb5(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v11:BasicObject = LoadArg :self@0
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v11, v12, v13)
        bb3(v20:BasicObject, v21:BasicObject, v22:NilClass):
          v26:Fixnum[1] = Const Value(1)
          Jump bb5(v20, v26, v26)
        bb4():
          EntryPoint JIT(1)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :a@1
          v18:NilClass = Const Value(nil)
          Jump bb5(v16, v17, v18)
        bb5(v31:BasicObject, v32:BasicObject, v33:NilClass|Fixnum):
          v39:ArrayExact = NewArray v32, v33
          CheckInterrupts
          Return v39
        ");
    }

    #[test]
    fn test_setlocal_in_default_args_with_tracepoint() {
        eval("
            def test(a = (b = 1)) = [a, b]
            TracePoint.new(:line) {}.enable
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:NilClass = Const Value(nil)
          v5:CPtr = LoadPC
          v6:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v7:CBool = IsBitEqual v5, v6
          IfTrue v7, bb3(v1, v3, v4)
          Jump bb5(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v11:BasicObject = LoadArg :self@0
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v11, v12, v13)
        bb3(v20:BasicObject, v21:BasicObject, v22:NilClass):
          SideExit UnhandledYARVInsn(trace_putobject_INT2FIX_1_)
        bb4():
          EntryPoint JIT(1)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :a@1
          v18:NilClass = Const Value(nil)
          Jump bb5(v16, v17, v18)
        bb5(v27:BasicObject, v28:BasicObject, v29:NilClass):
          v35:ArrayExact = NewArray v28, v29
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_setlocal_in_default_args_with_side_exit() {
        eval("
            def test(a = (def foo = nil)) = a
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:CPtr = LoadPC
          v5:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v6:CBool = IsBitEqual v4, v5
          IfTrue v6, bb3(v1, v3)
          Jump bb5(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:NilClass = Const Value(nil)
          Jump bb3(v10, v11)
        bb3(v17:BasicObject, v18:BasicObject):
          SideExit UnhandledYARVInsn(definemethod)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :a@1
          Jump bb5(v14, v15)
        bb5(v23:BasicObject, v24:BasicObject):
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_setlocal_cyclic_default_args() {
        eval("
            def test = proc { |a=a| a }
        ");
        assert_snapshot!(hir_string_proc("test"), @"
        fn block in test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:NilClass = Const Value(nil)
          Jump bb3(v6, v7)
        bb4():
          EntryPoint JIT(1)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :a@1
          Jump bb3(v10, v11)
        bb3(v13:BasicObject, v14:BasicObject):
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn defined_ivar() {
        eval("
            def test = defined?(@foo)
        ");
        assert_contains_opcode("test", YARVINSN_definedivar);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact|NilClass = DefinedIvar v6, :@foo
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn if_defined_ivar() {
        eval("
            def test
              if defined?(@foo)
                3
              else
                4
              end
            end
        ");
        assert_contains_opcode("test", YARVINSN_definedivar);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:TrueClass|NilClass = DefinedIvar v6, :@foo
          CheckInterrupts
          v13:CBool = Test v10
          v14:NilClass = RefineType v10, Falsy
          IfFalse v13, bb4(v6)
          v16:TrueClass = RefineType v10, Truthy
          v19:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v19
        bb4(v24:BasicObject):
          v28:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn defined() {
        eval("
            def test = return defined?(SeaChange), defined?(favourite), defined?($ruby)
        ");
        assert_contains_opcode("test", YARVINSN_defined);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:NilClass = Const Value(nil)
          v12:StringExact|NilClass = Defined constant, v10
          v15:StringExact|NilClass = Defined func, v6
          v17:NilClass = Const Value(nil)
          v19:StringExact|NilClass = Defined global-variable, v17
          v21:ArrayExact = NewArray v12, v15, v19
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn defined_yield_in_method_local_iseq_returns_defined() {
        eval("
            def test = defined?(yield)
        ");
        assert_contains_opcode("test", YARVINSN_defined);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:NilClass = Const Value(nil)
          v12:StringExact|NilClass = Defined yield, v10
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn defined_yield_in_non_method_local_iseq_returns_nil() {
        eval("
            define_method(:test) { defined?(yield) }
        ");
        assert_contains_opcode("test", YARVINSN_defined);
        assert_snapshot!(hir_string("test"), @r"
        fn block in <compiled>@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:NilClass = Const Value(nil)
          v12:NilClass = Const Value(nil)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_return_const() {
        eval("
            def test(cond)
              if cond
                3
              else
                4
              end
            end
        ");
        assert_contains_opcode("test", YARVINSN_leave);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :cond@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :cond@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          IfFalse v16, bb4(v9, v17)
          v19:Truthy = RefineType v10, Truthy
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
        bb4(v27:BasicObject, v28:Falsy):
          v32:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_merge_const() {
        eval("
            def test(cond)
              if cond
                result = 3
              else
                result = 4
              end
              result
            end
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :cond@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :cond@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          CheckInterrupts
          v19:CBool = Test v12
          v20:Falsy = RefineType v12, Falsy
          IfFalse v19, bb4(v11, v20, v13)
          v22:Truthy = RefineType v12, Truthy
          v25:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Jump bb5(v11, v22, v25)
        bb4(v30:BasicObject, v31:Falsy, v32:NilClass):
          v36:Fixnum[4] = Const Value(4)
          Jump bb5(v30, v31, v36)
        bb5(v39:BasicObject, v40:BasicObject, v41:Fixnum):
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_opt_plus_fixnum() {
        eval("
            def test(a, b) = a + b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_plus);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :+, v13 # SendFallbackReason: Uncategorized(opt_plus)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_minus_fixnum() {
        eval("
            def test(a, b) = a - b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_minus);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :-, v13 # SendFallbackReason: Uncategorized(opt_minus)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_mult_fixnum() {
        eval("
            def test(a, b) = a * b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_mult);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :*, v13 # SendFallbackReason: Uncategorized(opt_mult)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_div_fixnum() {
        eval("
            def test(a, b) = a / b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_div);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :/, v13 # SendFallbackReason: Uncategorized(opt_div)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_mod_fixnum() {
        eval("
            def test(a, b) = a % b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_mod);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :%, v13 # SendFallbackReason: Uncategorized(opt_mod)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_eq_fixnum() {
        eval("
            def test(a, b) = a == b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_eq);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :==, v13 # SendFallbackReason: Uncategorized(opt_eq)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_neq_fixnum() {
        eval("
            def test(a, b) = a != b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_neq);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :!=, v13 # SendFallbackReason: Uncategorized(opt_neq)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_lt_fixnum() {
        eval("
            def test(a, b) = a < b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_lt);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :<, v13 # SendFallbackReason: Uncategorized(opt_lt)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_le_fixnum() {
        eval("
            def test(a, b) = a <= b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_le);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :<=, v13 # SendFallbackReason: Uncategorized(opt_le)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_gt_fixnum() {
        eval("
            def test(a, b) = a > b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_gt);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :>, v13 # SendFallbackReason: Uncategorized(opt_gt)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_loop() {
        eval("
            def test
              result = 0
              times = 10
              while times > 0
                result = result + 1
                times = times - 1
              end
              result
            end
            test
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          v3:NilClass = Const Value(nil)
          Jump bb3(v1, v2, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:NilClass = Const Value(nil)
          v8:NilClass = Const Value(nil)
          Jump bb3(v6, v7, v8)
        bb3(v10:BasicObject, v11:NilClass, v12:NilClass):
          v16:Fixnum[0] = Const Value(0)
          v20:Fixnum[10] = Const Value(10)
          CheckInterrupts
          Jump bb5(v10, v16, v20)
        bb5(v26:BasicObject, v27:BasicObject, v28:BasicObject):
          v32:Fixnum[0] = Const Value(0)
          v35:BasicObject = Send v28, :>, v32 # SendFallbackReason: Uncategorized(opt_gt)
          CheckInterrupts
          v38:CBool = Test v35
          v39:Truthy = RefineType v35, Truthy
          IfTrue v38, bb4(v26, v27, v28)
          v41:Falsy = RefineType v35, Falsy
          v43:NilClass = Const Value(nil)
          CheckInterrupts
          Return v27
        bb4(v51:BasicObject, v52:BasicObject, v53:BasicObject):
          v58:Fixnum[1] = Const Value(1)
          v61:BasicObject = Send v52, :+, v58 # SendFallbackReason: Uncategorized(opt_plus)
          v66:Fixnum[1] = Const Value(1)
          v69:BasicObject = Send v53, :-, v66 # SendFallbackReason: Uncategorized(opt_minus)
          Jump bb5(v51, v61, v69)
        ");
    }

    #[test]
    fn test_opt_ge_fixnum() {
        eval("
            def test(a, b) = a >= b
            test(1, 2); test(1, 2)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ge);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :>=, v13 # SendFallbackReason: Uncategorized(opt_ge)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_display_types() {
        eval("
            def test
              cond = true
              if cond
                3
              else
                4
              end
            end
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:BasicObject, v9:NilClass):
          v13:TrueClass = Const Value(true)
          CheckInterrupts
          v19:CBool[true] = Test v13
          v20 = RefineType v13, Falsy
          IfFalse v19, bb4(v8, v20)
          v22:TrueClass = RefineType v13, Truthy
          v25:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v25
        bb4(v30, v31):
          v35 = Const Value(4)
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_send_without_block() {
        eval("
            def bar(a, b)
              a+b
            end
            def test
              bar(2, 3)
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_send_without_block);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[2] = Const Value(2)
          v13:Fixnum[3] = Const Value(3)
          v15:BasicObject = Send v6, :bar, v11, v13 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_send_with_block() {
        eval("
            def test(a)
              a.each {|item|
                item
              }
            end
            test([1,2,3])
        ");
        assert_contains_opcode("test", YARVINSN_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:BasicObject = Send v10, 0x1008, :each # SendFallbackReason: Uncategorized(send)
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :a@0x1030
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_intern_interpolated_symbol() {
        eval(r#"
            def test
              :"foo#{123}"
            end
        "#);
        assert_contains_opcode("test", YARVINSN_intern);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:Fixnum[123] = Const Value(123)
          v15:BasicObject = ObjToString v12
          v17:String = AnyToString v12, str: v15
          v19:StringExact = StringConcat v10, v17
          v21:Symbol = StringIntern v19
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn different_objects_get_addresses() {
        eval("def test = unknown_method([0], [1], '2', '2')");

        // The 2 string literals have the same address because they're deduped.
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:ArrayExact = ArrayDup v11
          v14:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v15:ArrayExact = ArrayDup v14
          v17:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v18:StringExact = StringCopy v17
          v20:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v21:StringExact = StringCopy v20
          v23:BasicObject = Send v6, :unknown_method, v12, v15, v18, v21 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_cant_compile_splat() {
        eval("
            def test(a) = foo(*a)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:ArrayExact = ToArray v10
          v18:BasicObject = Send v9, :foo, v16 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_compile_block_arg() {
        eval("
            def test(a) = foo(&a)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = Send v9, 0x1008, :foo, v10 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_cant_compile_kwarg() {
        eval("
            def test(a) = foo(a: 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          v17:BasicObject = Send v9, :foo, v15 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_cant_compile_kw_splat() {
        eval("
            def test(a) = foo(**a)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = Send v9, :foo, v10 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v16
        ");
    }

    // TODO(max): Figure out how to generate a call with TAILCALL flag

    #[test]
    fn test_compile_super() {
        eval("
            def test = super()
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:BasicObject = InvokeSuper v6, 0x1000 # SendFallbackReason: Uncategorized(invokesuper)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_compile_zsuper() {
        eval("
            def test = super
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:BasicObject = InvokeSuper v6, 0x1000 # SendFallbackReason: Uncategorized(invokesuper)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_cant_compile_super_nil_blockarg() {
        eval("
            def test = super(&nil)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:NilClass = Const Value(nil)
          v13:BasicObject = InvokeSuper v6, 0x1000, v11 # SendFallbackReason: Uncategorized(invokesuper)
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_compile_super_forward() {
        eval("
            def test(...) = super(...)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = InvokeSuperForward v9, 0x1008, v10 # SendFallbackReason: Uncategorized(invokesuperforward)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_compile_super_forward_with_block() {
        eval("
            def test(...) = super { |x| x }
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = InvokeSuperForward v9, 0x1008, v10 # SendFallbackReason: Uncategorized(invokesuperforward)
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :...@0x1010
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_compile_super_forward_with_use() {
        eval("
            def test(...) = super(...) + 1
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = InvokeSuperForward v9, 0x1008, v10 # SendFallbackReason: Uncategorized(invokesuperforward)
          v18:Fixnum[1] = Const Value(1)
          v21:BasicObject = Send v16, :+, v18 # SendFallbackReason: Uncategorized(opt_plus)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_compile_super_forward_with_arg() {
        eval("
            def test(...) = super(1, ...)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          v18:BasicObject = InvokeSuperForward v9, 0x1008, v15, v10 # SendFallbackReason: Uncategorized(invokesuperforward)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_compile_forwardable() {
        eval("def forwardable(...) = nil");
        assert_snapshot!(hir_string("forwardable"), @"
        fn forwardable@<compiled>:1:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:NilClass = Const Value(nil)
          CheckInterrupts
          Return v14
        ");
    }

    // TODO(max): Figure out how to generate a call with OPT_SEND flag

    #[test]
    fn test_cant_compile_kw_splat_mut() {
        eval("
            def test(a) = foo **a, b: 1
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Class[VMFrozenCore] = Const Value(VALUE(0x1008))
          v17:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v22:BasicObject = Send v15, :core#hash_merge_kwd, v17, v10 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v24:Class[VMFrozenCore] = Const Value(VALUE(0x1008))
          v27:StaticSymbol[:b] = Const Value(VALUE(0x1010))
          v29:Fixnum[1] = Const Value(1)
          v31:BasicObject = Send v24, :core#hash_merge_ptr, v22, v27, v29 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v33:BasicObject = Send v9, :foo, v31 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_cant_compile_splat_mut() {
        eval("
            def test(*) = foo *, 1
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:ArrayExact = LoadField v2, :*@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :*@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:ArrayExact = ToNewArray v10
          v18:Fixnum[1] = Const Value(1)
          ArrayPush v16, v18
          v22:BasicObject = Send v9, :foo, v16 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_compile_forwarding() {
        eval("
            def test(...) = foo(...)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :...@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :...@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = SendForward v9, 0x1008, :foo, v10 # SendFallbackReason: Uncategorized(sendforward)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_compile_triple_dots_with_positional_args() {
        eval("
            def test(a, ...) = foo(a, ...)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:ArrayExact = LoadField v2, :*@0x1001
          v5:BasicObject = LoadField v2, :**@0x1002
          v6:BasicObject = LoadField v2, :&@0x1003
          v7:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6, v7)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :a@1
          v12:BasicObject = LoadArg :*@2
          v13:BasicObject = LoadArg :**@3
          v14:BasicObject = LoadArg :&@4
          v15:NilClass = Const Value(nil)
          Jump bb3(v10, v11, v12, v13, v14, v15)
        bb3(v17:BasicObject, v18:BasicObject, v19:BasicObject, v20:BasicObject, v21:BasicObject, v22:NilClass):
          v29:ArrayExact = ToArray v19
          PatchPoint NoEPEscape(test)
          v34:CPtr = GetEP 0
          v35:CInt64 = LoadField v34, :_env_data_index_flags@0x1004
          v36:CInt64 = GuardNoBitsSet v35, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v37:CInt64 = LoadField v34, :_env_data_index_specval@0x1005
          v38:CInt64 = GuardAnyBitSet v37, CUInt64(1)
          v39:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          SideExit SplatKwNotProfiled
        ");
    }

    #[test]
    fn test_opt_new() {
        eval("
            class C; end
            def test = C.new
        ");
        assert_contains_opcode("test", YARVINSN_opt_new);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = GetConstantPath 0x1000
          v12:NilClass = Const Value(nil)
          v15:CBool = IsMethodCFunc v10, :new
          IfFalse v15, bb4(v6, v12, v10)
          v17:HeapBasicObject = ObjectAlloc v10
          v19:BasicObject = Send v17, :initialize # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Jump bb5(v6, v17, v19)
        bb4(v23:BasicObject, v24:NilClass, v25:BasicObject):
          v28:BasicObject = Send v25, :new # SendFallbackReason: Uncategorized(opt_send_without_block)
          Jump bb5(v23, v28, v24)
        bb5(v31:BasicObject, v32:BasicObject, v33:BasicObject):
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_opt_newarray_send_max_no_elements() {
        eval("
            def test = [].max
        ");
        // TODO(max): Rewrite to nil
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX)
          v11:BasicObject = ArrayMax
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_newarray_send_max() {
        eval("
            def test(a,b) = [a,b].max
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX)
          v20:BasicObject = ArrayMax v12, v13
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_opt_newarray_send_max_redefined() {
        eval("
            class Array
              alias_method :old_max, :max
              def max
                old_max * 2
              end
            end

            def test(a,b) = [a,b].max
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX))
        ");
    }

    #[test]
    fn test_opt_newarray_send_min() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].min
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          SideExit UnhandledNewarraySend(MIN)
        ");
    }

    #[test]
    fn test_opt_newarray_send_hash() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].hash
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_HASH)
          v33:Fixnum = ArrayHash v16, v17
          PatchPoint NoEPEscape(test)
          v40:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v41:ArrayExact = ArrayDup v40
          v43:BasicObject = Send v15, :puts, v41 # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_opt_newarray_send_hash_redefined() {
        eval("
            Array.class_eval { def hash = 42 }

            def test(a,b)
              sum = a+b
              result = [a,b].hash
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_HASH))
        ");
    }

    #[test]
    fn test_opt_newarray_send_pack() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].pack 'C'
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          v32:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v33:StringExact = StringCopy v32
          SideExit UnhandledNewarraySend(PACK)
        ");
    }

    #[test]
    fn test_opt_newarray_send_pack_buffer() {
        eval(r#"
            def test(a,b)
              sum = a+b
              buf = ""
              [a,b].pack 'C', buffer: buf
              buf
            end
        "#);
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          v30:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v31:StringExact = StringCopy v30
          v37:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v38:StringExact = StringCopy v37
          v40:CPtr = GetEP 0
          v41:BasicObject = LoadField v40, :buf@0x1018
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_PACK)
          v44:String = ArrayPackBuffer v16, v17, fmt: v38, buf: v41
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_opt_newarray_send_pack_buffer_redefined() {
        eval(r#"
            class Array
              def pack(fmt, buffer: nil) = 5
            end
            def test(a,b)
              sum = a+b
              buf = ""
              [a,b].pack 'C', buffer: buf
              buf
            end
        "#);
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          v30:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v31:StringExact = StringCopy v30
          v37:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v38:StringExact = StringCopy v37
          v40:CPtr = GetEP 0
          v41:BasicObject = LoadField v40, :buf@0x1018
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_PACK))
        ");
    }

    #[test]
    fn test_opt_newarray_send_include_p() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].include? b
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P)
          v34:BoolExact = ArrayInclude v16, v17 | v17
          PatchPoint NoEPEscape(test)
          v41:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v42:ArrayExact = ArrayDup v41
          v44:BasicObject = Send v15, :puts, v42 # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_opt_newarray_send_include_p_redefined() {
        eval("
            class Array
              alias_method :old_include?, :include?
              def include?(x)
                old_include?(x)
              end
            end

            def test(a,b)
              sum = a+b
              result = [a,b].include? b
              puts [1,2,3]
              result
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :a@1
          v11:BasicObject = LoadArg :b@2
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass, v19:NilClass):
          v26:BasicObject = Send v16, :+, v17 # SendFallbackReason: Uncategorized(opt_plus)
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P))
        ");
    }

    #[test]
    fn test_opt_duparray_send_include_p() {
        eval("
            def test(x)
              [:a, :b].include?(x)
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_duparray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P)
          v16:BoolExact = DupArrayInclude VALUE(0x1008) | v10
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_opt_duparray_send_include_p_redefined() {
        eval("
            class Array
              alias_method :old_include?, :include?
              def include?(x)
                old_include?(x)
              end
            end
            def test(x)
              [:a, :b].include?(x)
            end
        ");
        assert_contains_opcode("test", YARVINSN_opt_duparray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P))
        ");
    }

    #[test]
    fn test_opt_length() {
        eval("
            def test(a,b) = [a,b].length
        ");
        assert_contains_opcode("test", YARVINSN_opt_length);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:ArrayExact = NewArray v12, v13
          v22:BasicObject = Send v19, :length # SendFallbackReason: Uncategorized(opt_length)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_opt_size() {
        eval("
            def test(a,b) = [a,b].size
        ");
        assert_contains_opcode("test", YARVINSN_opt_size);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:ArrayExact = NewArray v12, v13
          v22:BasicObject = Send v19, :size # SendFallbackReason: Uncategorized(opt_size)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_getconstant() {
        eval("
            def test(klass)
              klass::ARGV
            end
        ");
        assert_contains_opcode("test", YARVINSN_getconstant);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :klass@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :klass@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:FalseClass = Const Value(false)
          v17:BasicObject = GetConstant v10, :ARGV, v15
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
            test
        ");
        assert_contains_opcode("test", YARVINSN_getinstancevariable);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          v11:BasicObject = GetIvar v6, :@foo
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_setinstancevariable() {
        eval("
            def test = @foo = 1
            test
        ");
        assert_contains_opcode("test", YARVINSN_setinstancevariable);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          SetIvar v6, :@foo, v10
          v15:HeapBasicObject = RefineType v6, HeapBasicObject
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_set_ivar_rescue_frozen() {
        let result = eval("
            class Foo
              attr_accessor :bar
              def initialize
                @bar = 1
                freeze
              end
            end

            def test(foo)
              begin
                foo.bar = 2
              rescue FrozenError
              end
            end

            foo = Foo.new
            test(foo)
            test(foo)

            foo.bar
        ");
        assert_eq!(VALUE::fixnum_from_usize(1), result);
    }

    #[test]
    fn test_getclassvariable() {
        eval("
            class Foo
              def self.test = @@foo
            end
        ");
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("Foo", "test"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_getclassvariable), "iseq Foo.test does not contain getclassvariable");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = GetClassVar :@@foo
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_setclassvariable() {
        eval("
            class Foo
              def self.test = @@foo = 42
            end
        ");
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("Foo", "test"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_setclassvariable), "iseq Foo.test does not contain setclassvariable");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[42] = Const Value(42)
          SetClassVar :@@foo, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_setglobal() {
        eval("
            def test = $foo = 1
            test
        ");
        assert_contains_opcode("test", YARVINSN_setglobal);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          SetGlobal :$foo, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_getglobal() {
        eval("
            def test = $foo
            test
        ");
        assert_contains_opcode("test", YARVINSN_getglobal);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = GetGlobal :$foo
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_getblockparam() {
        eval("
            def test(&block) = block
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :block@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :block@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:CPtr = GetEP 0
          v15:CBool = IsBlockParamModified v14
          IfTrue v15, bb4(v9, v10)
          Jump bb5(v9, v10)
        bb4(v16:BasicObject, v17:BasicObject):
          v24:CPtr = GetEP 0
          v25:BasicObject = LoadField v24, :block@0x1001
          Jump bb6(v16, v25, v25)
        bb5(v19:BasicObject, v20:BasicObject):
          v27:BasicObject = GetBlockParam :block, l0, EP@3
          Jump bb6(v19, v27, v27)
        bb6(v29:BasicObject, v30:BasicObject, v31:BasicObject):
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_getblockparam_nested_block() {
        eval("
            def test(&block)
              proc do
                block
              end
            end
        ");
        assert_snapshot!(hir_string_proc("test"), @"
        fn block in test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:CPtr = GetEP 1
          v11:CBool = IsBlockParamModified v10
          IfTrue v11, bb4(v6)
          Jump bb5(v6)
        bb4(v12:BasicObject):
          v18:CPtr = GetEP 1
          v19:BasicObject = LoadField v18, :block@0x1000
          Jump bb6(v12, v19)
        bb5(v14:BasicObject):
          v21:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb6(v14, v21)
        bb6(v23:BasicObject, v24:BasicObject):
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_splatkw_unprofiled_side_exits() {
        eval("
            def foo(**kw, &b) = kw
            def test(**kw, &b) = foo(**kw, &b)
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :kw@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :kw@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:CPtr = GetEP 0
          v20:CInt64 = LoadField v19, :_env_data_index_flags@0x1002
          v21:CInt64 = GuardNoBitsSet v20, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v22:CInt64 = LoadField v19, :_env_data_index_specval@0x1003
          v23:CInt64 = GuardAnyBitSet v22, CUInt64(1)
          v24:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          SideExit SplatKwNotProfiled
        ");
    }

    #[test]
    fn test_splatkw_nil_guards_nil() {
        eval("
            def foo(a, ...) = a
            def test(a, ...) = foo(a, ...)
            test(1)
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:ArrayExact = LoadField v2, :*@0x1001
          v5:BasicObject = LoadField v2, :**@0x1002
          v6:BasicObject = LoadField v2, :&@0x1003
          v7:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6, v7)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :a@1
          v12:BasicObject = LoadArg :*@2
          v13:BasicObject = LoadArg :**@3
          v14:BasicObject = LoadArg :&@4
          v15:NilClass = Const Value(nil)
          Jump bb3(v10, v11, v12, v13, v14, v15)
        bb3(v17:BasicObject, v18:BasicObject, v19:BasicObject, v20:BasicObject, v21:BasicObject, v22:NilClass):
          v29:ArrayExact = ToArray v19
          PatchPoint NoEPEscape(test)
          v34:CPtr = GetEP 0
          v35:CInt64 = LoadField v34, :_env_data_index_flags@0x1004
          v36:CInt64 = GuardNoBitsSet v35, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v37:CInt64 = LoadField v34, :_env_data_index_specval@0x1005
          v38:CInt64[0] = GuardBitEquals v37, CInt64(0)
          v39:NilClass = Const Value(nil)
          v41:NilClass = GuardType v20, NilClass
          v43:BasicObject = Send v17, 0x1004, :foo, v18, v29, v41, v39 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v43
        ");
    }

    #[test]
    fn test_splatkw_empty_hash_guards_hash() {
        eval("
            def foo(**kw, &b) = kw
            def test(**kw, &b) = foo(**kw, &b)
            test(&proc {})
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :kw@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :kw@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:CPtr = GetEP 0
          v20:CInt64 = LoadField v19, :_env_data_index_flags@0x1002
          v21:CInt64 = GuardNoBitsSet v20, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v22:CInt64 = LoadField v19, :_env_data_index_specval@0x1003
          v23:CInt64 = GuardAnyBitSet v22, CUInt64(1)
          v24:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          v26:HashExact = GuardType v12, HashExact
          v28:BasicObject = Send v11, 0x1002, :foo, v26, v24 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_splatkw_hash_guards_hash() {
        eval("
            def foo(**kw, &b) = kw
            def test(**kw, &b) = foo(**kw, &b)
            test(a: 1, &proc {})
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :kw@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :kw@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:CPtr = GetEP 0
          v20:CInt64 = LoadField v19, :_env_data_index_flags@0x1002
          v21:CInt64 = GuardNoBitsSet v20, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v22:CInt64 = LoadField v19, :_env_data_index_specval@0x1003
          v23:CInt64 = GuardAnyBitSet v22, CUInt64(1)
          v24:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          v26:HashExact = GuardType v12, HashExact
          v28:BasicObject = Send v11, 0x1002, :foo, v26, v24 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_splatkw_polymorphic_side_exits() {
        set_call_threshold(3);
        eval("
            def foo(a, ...) = a
            def test(a, ...) = foo(a, ...)
            test(1)
            test(1, b: 2)
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:ArrayExact = LoadField v2, :*@0x1001
          v5:BasicObject = LoadField v2, :**@0x1002
          v6:BasicObject = LoadField v2, :&@0x1003
          v7:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6, v7)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :a@1
          v12:BasicObject = LoadArg :*@2
          v13:BasicObject = LoadArg :**@3
          v14:BasicObject = LoadArg :&@4
          v15:NilClass = Const Value(nil)
          Jump bb3(v10, v11, v12, v13, v14, v15)
        bb3(v17:BasicObject, v18:BasicObject, v19:BasicObject, v20:BasicObject, v21:BasicObject, v22:NilClass):
          v29:ArrayExact = ToArray v19
          PatchPoint NoEPEscape(test)
          v34:CPtr = GetEP 0
          v35:CInt64 = LoadField v34, :_env_data_index_flags@0x1004
          v36:CInt64 = GuardNoBitsSet v35, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v37:CInt64 = LoadField v34, :_env_data_index_specval@0x1005
          v38:CInt64[0] = GuardBitEquals v37, CInt64(0)
          v39:NilClass = Const Value(nil)
          SideExit SplatKwPolymorphic
        ");
    }

    #[test]
    fn test_splatkw_with_non_hash_side_exits() {
        eval("
            def foo(a:) = a
            def test(obj, &block) = foo(**obj, &block)
            obj = Object.new
            def obj.to_hash = { a: 1 }
            test(obj) { 2 }
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :obj@0x1000
          v4:BasicObject = LoadField v2, :block@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :obj@1
          v9:BasicObject = LoadArg :block@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:CPtr = GetEP 0
          v20:CInt64 = LoadField v19, :_env_data_index_flags@0x1002
          v21:CInt64 = GuardNoBitsSet v20, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v22:CInt64 = LoadField v19, :_env_data_index_specval@0x1003
          v23:CInt64 = GuardAnyBitSet v22, CUInt64(1)
          v24:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          SideExit SplatKwNotNilOrHash
        ");
    }

    #[test]
    fn test_splatarray_mut() {
        eval("
            def test(a) = [*a]
        ");
        assert_contains_opcode("test", YARVINSN_splatarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:ArrayExact = ToNewArray v10
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_concattoarray() {
        eval("
            def test(a) = [1, *a]
        ");
        assert_contains_opcode("test", YARVINSN_concattoarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:Fixnum[1] = Const Value(1)
          v16:ArrayExact = NewArray v14
          v19:ArrayExact = ToArray v10
          ArrayExtend v16, v19
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_pushtoarray_one_element() {
        eval("
            def test(a) = [*a, 1]
        ");
        assert_contains_opcode("test", YARVINSN_pushtoarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:ArrayExact = ToNewArray v10
          v17:Fixnum[1] = Const Value(1)
          ArrayPush v15, v17
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_pushtoarray_multiple_elements() {
        eval("
            def test(a) = [*a, 1, 2, 3]
        ");
        assert_contains_opcode("test", YARVINSN_pushtoarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :a@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:ArrayExact = ToNewArray v10
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[2] = Const Value(2)
          v21:Fixnum[3] = Const Value(3)
          ArrayPush v15, v17
          ArrayPush v15, v19
          ArrayPush v15, v21
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_aset() {
        eval("
            def test(a, b) = a[b] = 1
        ");
        assert_contains_opcode("test", YARVINSN_opt_aset);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v17:NilClass = Const Value(nil)
          v21:Fixnum[1] = Const Value(1)
          v25:BasicObject = Send v12, :[]=, v13, v21 # SendFallbackReason: Uncategorized(opt_aset)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_aref() {
        eval("
            def test(a, b) = a[b]
        ");
        assert_contains_opcode("test", YARVINSN_opt_aref);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:BasicObject = LoadField v2, :b@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:BasicObject = LoadArg :b@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :[], v13 # SendFallbackReason: Uncategorized(opt_aref)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn opt_empty_p() {
        eval("
            def test(x) = x.empty?
        ");
        assert_contains_opcode("test", YARVINSN_opt_empty_p);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = Send v10, :empty? # SendFallbackReason: Uncategorized(opt_empty_p)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn opt_succ() {
        eval("
            def test(x) = x.succ
        ");
        assert_contains_opcode("test", YARVINSN_opt_succ);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = Send v10, :succ # SendFallbackReason: Uncategorized(opt_succ)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn opt_and() {
        eval("
            def test(x, y) = x & y
        ");
        assert_contains_opcode("test", YARVINSN_opt_and);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:BasicObject = LoadField v2, :y@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:BasicObject = LoadArg :y@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :&, v13 # SendFallbackReason: Uncategorized(opt_and)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn opt_or() {
        eval("
            def test(x, y) = x | y
        ");
        assert_contains_opcode("test", YARVINSN_opt_or);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:BasicObject = LoadField v2, :y@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:BasicObject = LoadArg :y@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :|, v13 # SendFallbackReason: Uncategorized(opt_or)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn opt_not() {
        eval("
            def test(x) = !x
        ");
        assert_contains_opcode("test", YARVINSN_opt_not);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:BasicObject = Send v10, :! # SendFallbackReason: Uncategorized(opt_not)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn opt_regexpmatch2() {
        eval("
            def test(regexp, matchee) = regexp =~ matchee
        ");
        assert_contains_opcode("test", YARVINSN_opt_regexpmatch2);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :regexp@0x1000
          v4:BasicObject = LoadField v2, :matchee@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :regexp@1
          v9:BasicObject = LoadArg :matchee@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v20:BasicObject = Send v12, :=~, v13 # SendFallbackReason: Uncategorized(opt_regexpmatch2)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    // Tests for ConstBase requires either constant or class definition, both
    // of which can't be performed inside a method.
    fn test_putspecialobject_vm_core_and_cbase() {
        eval("
            def test
              alias aliased __callee__
            end
        ");
        assert_contains_opcode("test", YARVINSN_putspecialobject);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Class[VMFrozenCore] = Const Value(VALUE(0x1000))
          v12:BasicObject = PutSpecialObject CBase
          v14:StaticSymbol[:aliased] = Const Value(VALUE(0x1008))
          v16:StaticSymbol[:__callee__] = Const Value(VALUE(0x1010))
          v18:BasicObject = Send v10, :core#set_method_alias, v12, v14, v16 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn opt_reverse() {
        eval("
            def reverse_odd
              a, b, c = @a, @b, @c
              [a, b, c]
            end

            def reverse_even
              a, b, c, d = @a, @b, @c, @d
              [a, b, c, d]
            end
        ");
        assert_contains_opcode("reverse_odd", YARVINSN_opt_reverse);
        assert_contains_opcode("reverse_even", YARVINSN_opt_reverse);
        assert_snapshot!(hir_strings!("reverse_odd", "reverse_even"), @r"
        fn reverse_odd@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          v3:NilClass = Const Value(nil)
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v2, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:NilClass = Const Value(nil)
          v9:NilClass = Const Value(nil)
          v10:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9, v10)
        bb3(v12:BasicObject, v13:NilClass, v14:NilClass, v15:NilClass):
          PatchPoint SingleRactorMode
          v20:BasicObject = GetIvar v12, :@a
          PatchPoint SingleRactorMode
          v23:BasicObject = GetIvar v12, :@b
          PatchPoint SingleRactorMode
          v26:BasicObject = GetIvar v12, :@c
          PatchPoint NoEPEscape(reverse_odd)
          v38:ArrayExact = NewArray v20, v23, v26
          CheckInterrupts
          Return v38

        fn reverse_even@<compiled>:8:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          v3:NilClass = Const Value(nil)
          v4:NilClass = Const Value(nil)
          v5:NilClass = Const Value(nil)
          Jump bb3(v1, v2, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:NilClass = Const Value(nil)
          v10:NilClass = Const Value(nil)
          v11:NilClass = Const Value(nil)
          v12:NilClass = Const Value(nil)
          Jump bb3(v8, v9, v10, v11, v12)
        bb3(v14:BasicObject, v15:NilClass, v16:NilClass, v17:NilClass, v18:NilClass):
          PatchPoint SingleRactorMode
          v23:BasicObject = GetIvar v14, :@a
          PatchPoint SingleRactorMode
          v26:BasicObject = GetIvar v14, :@b
          PatchPoint SingleRactorMode
          v29:BasicObject = GetIvar v14, :@c
          PatchPoint SingleRactorMode
          v32:BasicObject = GetIvar v14, :@d
          PatchPoint NoEPEscape(reverse_even)
          v46:ArrayExact = NewArray v23, v26, v29, v32
          CheckInterrupts
          Return v46
        ");
    }

    #[test]
    fn test_branchnil() {
        eval("
        def test(x) = x&.itself
        ");
        assert_contains_opcode("test", YARVINSN_branchnil);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v17:CBool = IsNil v10
          v18:NilClass = Const Value(nil)
          IfTrue v17, bb4(v9, v18, v18)
          v20:NotNil = RefineType v10, NotNil
          v22:BasicObject = Send v20, :itself # SendFallbackReason: Uncategorized(opt_send_without_block)
          Jump bb4(v9, v20, v22)
        bb4(v24:BasicObject, v25:BasicObject, v26:BasicObject):
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_infer_nilability_from_branchif() {
        eval("
        def test(x)
          if x
            x&.itself
          else
            4
          end
        end
        ");
        assert_contains_opcode("test", YARVINSN_branchnil);
        // Note that IsNil has as its operand a value that we know statically *cannot* be nil
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          IfFalse v16, bb4(v9, v17)
          v19:Truthy = RefineType v10, Truthy
          CheckInterrupts
          v25:CBool[false] = IsNil v19
          v26:NilClass = Const Value(nil)
          IfTrue v25, bb5(v9, v26, v26)
          v28:Truthy = RefineType v19, NotNil
          v30:BasicObject = Send v28, :itself # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v30
        bb4(v35:BasicObject, v36:Falsy):
          v40:Fixnum[4] = Const Value(4)
          Jump bb5(v35, v36, v40)
        bb5(v42:BasicObject, v43:Falsy, v44:Fixnum[4]):
          CheckInterrupts
          Return v44
        ");
    }

    #[test]
    fn test_infer_truthiness_from_branch() {
        eval("
        def test(x)
          if x
            if x
              if x
                3
              else
                4
              end
            else
              5
            end
          else
            6
          end
        end
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          IfFalse v16, bb6(v9, v17)
          v19:Truthy = RefineType v10, Truthy
          CheckInterrupts
          v24:CBool[true] = Test v19
          v25 = RefineType v19, Falsy
          IfFalse v24, bb5(v9, v25)
          v27:Truthy = RefineType v19, Truthy
          CheckInterrupts
          v32:CBool[true] = Test v27
          v33 = RefineType v27, Falsy
          IfFalse v32, bb4(v9, v33)
          v35:Truthy = RefineType v27, Truthy
          v38:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v38
        bb6(v43:BasicObject, v44:Falsy):
          v48:Fixnum[6] = Const Value(6)
          CheckInterrupts
          Return v48
        bb5(v53, v54):
          v58 = Const Value(5)
          CheckInterrupts
          Return v58
        bb4(v63, v64):
          v68 = Const Value(4)
          CheckInterrupts
          Return v68
        ");
    }

    #[test]
    fn test_invokebuiltin_delegate_annotated() {
        assert_contains_opcode("Float", YARVINSN_opt_invokebuiltin_delegate_leave);
        assert_snapshot!(hir_string("Float"), @"
        fn Float@<internal:kernel>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arg@0x1000
          v4:BasicObject = LoadField v2, :exception@0x1001
          v5:BasicObject = LoadField v2, :<empty>@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :arg@1
          v10:BasicObject = LoadArg :exception@2
          v11:CPtr = GetEP 0
          v12:BasicObject = LoadField v11, :<empty>@0x1003
          Jump bb3(v8, v9, v10, v12)
        bb3(v14:BasicObject, v15:BasicObject, v16:BasicObject, v17:BasicObject):
          v21:Float = InvokeBuiltin rb_f_float, v14, v15, v16
          Jump bb4(v14, v15, v16, v17, v21)
        bb4(v23:BasicObject, v24:BasicObject, v25:BasicObject, v26:BasicObject, v27:Float):
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_invokebuiltin_cexpr_annotated() {
        assert_contains_opcode("class", YARVINSN_opt_invokebuiltin_delegate_leave);
        assert_snapshot!(hir_string("class"), @r"
        fn class@<internal:kernel>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:HeapObject = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v10)
        bb4(v12:BasicObject, v13:HeapObject):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_invokebuiltin_delegate_with_args() {
        // Using an unannotated builtin to test InvokeBuiltin generation
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("Dir", "open"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_opt_invokebuiltin_delegate), "iseq Dir.open does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @"
        fn open@<internal:dir>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :name@0x1000
          v4:BasicObject = LoadField v2, :encoding@0x1001
          v5:BasicObject = LoadField v2, :<empty>@0x1002
          v6:BasicObject = LoadField v2, :block@0x1003
          v7:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6, v7)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :name@1
          v12:BasicObject = LoadArg :encoding@2
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :<empty>@0x1003
          v15:BasicObject = LoadArg :block@3
          v16:NilClass = Const Value(nil)
          Jump bb3(v10, v11, v12, v14, v15, v16)
        bb3(v18:BasicObject, v19:BasicObject, v20:BasicObject, v21:BasicObject, v22:BasicObject, v23:NilClass):
          v27:BasicObject = InvokeBuiltin dir_s_open, v18, v19, v20
          PatchPoint NoEPEscape(open)
          v33:CPtr = GetEP 0
          v34:CInt64 = LoadField v33, :_env_data_index_flags@0x1004
          v35:CInt64 = GuardNoBitsSet v34, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v36:CInt64 = LoadField v33, :_env_data_index_specval@0x1005
          v37:CInt64 = GuardAnyBitSet v36, CUInt64(1)
          v38:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          CheckInterrupts
          v41:CBool[true] = Test v38
          v42 = RefineType v38, Falsy
          IfFalse v41, bb4(v18, v19, v20, v21, v22, v27)
          v44:HeapObject[BlockParamProxy] = RefineType v38, Truthy
          v48:BasicObject = InvokeBlock, v27 # SendFallbackReason: Uncategorized(invokeblock)
          v51:BasicObject = InvokeBuiltin dir_s_close, v18, v27
          CheckInterrupts
          Return v48
        bb4(v57, v58, v59, v60, v61, v62):
          CheckInterrupts
          Return v62
        ");
    }

    #[test]
    fn test_invokebuiltin_delegate_without_args() {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("GC", "enable"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_opt_invokebuiltin_delegate_leave), "iseq GC.enable does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @r"
        fn enable@<internal:gc>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = InvokeBuiltin gc_enable, v6
          Jump bb4(v6, v10)
        bb4(v12:BasicObject, v13:BasicObject):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_invokebuiltin_with_args() {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("GC", "start"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_invokebuiltin), "iseq GC.start does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @"
        fn start@<internal:gc>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :full_mark@0x1000
          v4:BasicObject = LoadField v2, :immediate_mark@0x1001
          v5:BasicObject = LoadField v2, :immediate_sweep@0x1002
          v6:BasicObject = LoadField v2, :<empty>@0x1003
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :full_mark@1
          v11:BasicObject = LoadArg :immediate_mark@2
          v12:BasicObject = LoadArg :immediate_sweep@3
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :<empty>@0x1004
          Jump bb3(v9, v10, v11, v12, v14)
        bb3(v16:BasicObject, v17:BasicObject, v18:BasicObject, v19:BasicObject, v20:BasicObject):
          v27:FalseClass = Const Value(false)
          v29:BasicObject = InvokeBuiltin gc_start_internal, v16, v17, v18, v19, v27
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_invoke_leaf_builtin_symbol_name() {
        let iseq = crate::cruby::with_rubyvm(|| get_instance_method_iseq("Symbol", "name"));
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @r"
        fn name@<internal:symbol>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v10)
        bb4(v12:BasicObject, v13:StringExact):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_invoke_leaf_builtin_symbol_to_s() {
        let iseq = crate::cruby::with_rubyvm(|| get_instance_method_iseq("Symbol", "to_s"));
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @r"
        fn to_s@<internal:symbol>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v10)
        bb4(v12:BasicObject, v13:StringExact):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn dupn() {
        eval("
            def test(x) = (x[0, 1] ||= 2)
        ");
        assert_contains_opcode("test", YARVINSN_dupn);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:NilClass = Const Value(nil)
          v17:Fixnum[0] = Const Value(0)
          v19:Fixnum[1] = Const Value(1)
          v22:BasicObject = Send v10, :[], v17, v19 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          v26:CBool = Test v22
          v27:Truthy = RefineType v22, Truthy
          IfTrue v26, bb4(v9, v10, v14, v10, v17, v19, v27)
          v29:Falsy = RefineType v22, Falsy
          v32:Fixnum[2] = Const Value(2)
          v35:BasicObject = Send v10, :[]=, v17, v19, v32 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v32
        bb4(v41:BasicObject, v42:BasicObject, v43:NilClass, v44:BasicObject, v45:Fixnum[0], v46:Fixnum[1], v47:Truthy):
          CheckInterrupts
          Return v47
        ");
    }

    #[test]
    fn test_objtostring_anytostring() {
        eval("
            def test = \"#{1}\"
        ");
        assert_contains_opcode("test", YARVINSN_objtostring);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:Fixnum[1] = Const Value(1)
          v15:BasicObject = ObjToString v12
          v17:String = AnyToString v12, str: v15
          v19:StringExact = StringConcat v10, v17
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_string_concat() {
        eval(r##"
            def test = "#{1}#{2}#{3}"
        "##);
        assert_contains_opcode("test", YARVINSN_concatstrings);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v13:BasicObject = ObjToString v10
          v15:String = AnyToString v10, str: v13
          v17:Fixnum[2] = Const Value(2)
          v20:BasicObject = ObjToString v17
          v22:String = AnyToString v17, str: v20
          v24:Fixnum[3] = Const Value(3)
          v27:BasicObject = ObjToString v24
          v29:String = AnyToString v24, str: v27
          v31:StringExact = StringConcat v15, v22, v29
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_string_concat_empty() {
        eval(r##"
            def test = "#{}"
        "##);
        assert_contains_opcode("test", YARVINSN_concatstrings);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:NilClass = Const Value(nil)
          v15:BasicObject = ObjToString v12
          v17:String = AnyToString v12, str: v15
          v19:StringExact = StringConcat v10, v17
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_toregexp() {
        eval(r##"
            def test = /#{1}#{2}#{3}/
        "##);
        assert_contains_opcode("test", YARVINSN_toregexp);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v13:BasicObject = ObjToString v10
          v15:String = AnyToString v10, str: v13
          v17:Fixnum[2] = Const Value(2)
          v20:BasicObject = ObjToString v17
          v22:String = AnyToString v17, str: v20
          v24:Fixnum[3] = Const Value(3)
          v27:BasicObject = ObjToString v24
          v29:String = AnyToString v24, str: v27
          v31:RegexpExact = ToRegexp v15, v22, v29
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_toregexp_with_options() {
        eval(r##"
            def test = /#{1}#{2}/mixn
        "##);
        assert_contains_opcode("test", YARVINSN_toregexp);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v13:BasicObject = ObjToString v10
          v15:String = AnyToString v10, str: v13
          v17:Fixnum[2] = Const Value(2)
          v20:BasicObject = ObjToString v17
          v22:String = AnyToString v17, str: v20
          v24:RegexpExact = ToRegexp v15, v22, MULTILINE|IGNORECASE|EXTENDED|NOENCODING
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn throw() {
        eval("
            define_method(:throw_return) { return 1 }
            define_method(:throw_break) { break 2 }
        ");
        assert_contains_opcode("throw_return", YARVINSN_throw);
        assert_contains_opcode("throw_break", YARVINSN_throw);
        assert_snapshot!(hir_strings!("throw_return", "throw_break"), @r"
        fn block in <compiled>@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v12:Fixnum[1] = Const Value(1)
          Throw TAG_RETURN, v12

        fn block in <compiled>@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v12:Fixnum[2] = Const Value(2)
          Throw TAG_BREAK, v12
        ");
    }

    #[test]
    fn test_invokeblock() {
        eval(r#"
            def test
              yield
            end
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = InvokeBlock # SendFallbackReason: Uncategorized(invokeblock)
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_invokeblock_with_args() {
        eval(r#"
            def test(x, y)
              yield x, y
            end
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:BasicObject = LoadField v2, :y@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:BasicObject = LoadArg :y@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:BasicObject = InvokeBlock, v12, v13 # SendFallbackReason: Uncategorized(invokeblock)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_expandarray_no_splat() {
        eval(r#"
            def test(o)
              a, b = o
            end
        "#);
        assert_contains_opcode("test", YARVINSN_expandarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          v4:NilClass = Const Value(nil)
          v5:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :o@1
          v10:NilClass = Const Value(nil)
          v11:NilClass = Const Value(nil)
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:NilClass, v16:NilClass):
          v22:ArrayExact = GuardType v14, ArrayExact
          v23:CInt64 = ArrayLength v22
          v24:CInt64[2] = Const CInt64(2)
          v25:CInt64 = GuardGreaterEq v23, v24
          v26:CInt64[1] = Const CInt64(1)
          v27:BasicObject = ArrayAref v22, v26
          v28:CInt64[0] = Const CInt64(0)
          v29:BasicObject = ArrayAref v22, v28
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_expandarray_splat() {
        eval(r#"
            def test(o)
              a, *b = o
            end
        "#);
        assert_contains_opcode("test", YARVINSN_expandarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          v4:NilClass = Const Value(nil)
          v5:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :o@1
          v10:NilClass = Const Value(nil)
          v11:NilClass = Const Value(nil)
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:NilClass, v16:NilClass):
          SideExit UnhandledYARVInsn(expandarray)
        ");
    }

    #[test]
    fn test_expandarray_splat_post() {
        eval(r#"
            def test(o)
              a, *b, c = o
            end
        "#);
        assert_contains_opcode("test", YARVINSN_expandarray);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          v4:NilClass = Const Value(nil)
          v5:NilClass = Const Value(nil)
          v6:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v9:BasicObject = LoadArg :self@0
          v10:BasicObject = LoadArg :o@1
          v11:NilClass = Const Value(nil)
          v12:NilClass = Const Value(nil)
          v13:NilClass = Const Value(nil)
          Jump bb3(v9, v10, v11, v12, v13)
        bb3(v15:BasicObject, v16:BasicObject, v17:NilClass, v18:NilClass, v19:NilClass):
          SideExit UnhandledYARVInsn(expandarray)
        ");
    }

    #[test]
    fn test_checkkeyword_tests_fixnum_bit() {
        eval(r#"
            def test(kw: 1 + 1) = kw
        "#);
        assert_contains_opcode("test", YARVINSN_checkkeyword);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :kw@0x1000
          v4:BasicObject = LoadField v2, :<empty>@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :kw@1
          v9:CPtr = GetEP 0
          v10:BasicObject = LoadField v9, :<empty>@0x1002
          Jump bb3(v7, v8, v10)
        bb3(v12:BasicObject, v13:BasicObject, v14:BasicObject):
          v17:BoolExact = FixnumBitCheck v14, 0
          CheckInterrupts
          v20:CBool = Test v17
          v21:TrueClass = RefineType v17, Truthy
          IfTrue v20, bb4(v12, v13, v14)
          v23:FalseClass = RefineType v17, Falsy
          v25:Fixnum[1] = Const Value(1)
          v27:Fixnum[1] = Const Value(1)
          v30:BasicObject = Send v25, :+, v27 # SendFallbackReason: Uncategorized(opt_plus)
          Jump bb4(v12, v30, v14)
        bb4(v33:BasicObject, v34:BasicObject, v35:BasicObject):
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_checkkeyword_too_many_keywords_causes_side_exit() {
        eval(r#"
            def test(k1: k1, k2: k2, k3: k3, k4: k4, k5: k5,
            k6: k6, k7: k7, k8: k8, k9: k9, k10: k10, k11: k11,
            k12: k12, k13: k13, k14: k14, k15: k15, k16: k16,
            k17: k17, k18: k18, k19: k19, k20: k20, k21: k21,
            k22: k22, k23: k23, k24: k24, k25: k25, k26: k26,
            k27: k27, k28: k28, k29: k29, k30: k30, k31: k31,
            k32: k32, k33: k33) = k1
        "#);
        assert_contains_opcode("test", YARVINSN_checkkeyword);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :k1@0x1000
          v4:BasicObject = LoadField v2, :k2@0x1001
          v5:BasicObject = LoadField v2, :k3@0x1002
          v6:BasicObject = LoadField v2, :k4@0x1003
          v7:BasicObject = LoadField v2, :k5@0x1004
          v8:BasicObject = LoadField v2, :k6@0x1005
          v9:BasicObject = LoadField v2, :k7@0x1006
          v10:BasicObject = LoadField v2, :k8@0x1007
          v11:BasicObject = LoadField v2, :k9@0x1008
          v12:BasicObject = LoadField v2, :k10@0x1009
          v13:BasicObject = LoadField v2, :k11@0x100a
          v14:BasicObject = LoadField v2, :k12@0x100b
          v15:BasicObject = LoadField v2, :k13@0x100c
          v16:BasicObject = LoadField v2, :k14@0x100d
          v17:BasicObject = LoadField v2, :k15@0x100e
          v18:BasicObject = LoadField v2, :k16@0x100f
          v19:BasicObject = LoadField v2, :k17@0x1010
          v20:BasicObject = LoadField v2, :k18@0x1011
          v21:BasicObject = LoadField v2, :k19@0x1012
          v22:BasicObject = LoadField v2, :k20@0x1013
          v23:BasicObject = LoadField v2, :k21@0x1014
          v24:BasicObject = LoadField v2, :k22@0x1015
          v25:BasicObject = LoadField v2, :k23@0x1016
          v26:BasicObject = LoadField v2, :k24@0x1017
          v27:BasicObject = LoadField v2, :k25@0x1018
          v28:BasicObject = LoadField v2, :k26@0x1019
          v29:BasicObject = LoadField v2, :k27@0x101a
          v30:BasicObject = LoadField v2, :k28@0x101b
          v31:BasicObject = LoadField v2, :k29@0x101c
          v32:BasicObject = LoadField v2, :k30@0x101d
          v33:BasicObject = LoadField v2, :k31@0x101e
          v34:BasicObject = LoadField v2, :k32@0x101f
          v35:BasicObject = LoadField v2, :k33@0x1020
          v36:BasicObject = LoadField v2, :<empty>@0x1021
          Jump bb3(v1, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16, v17, v18, v19, v20, v21, v22, v23, v24, v25, v26, v27, v28, v29, v30, v31, v32, v33, v34, v35, v36)
        bb2():
          EntryPoint JIT(0)
          v39:BasicObject = LoadArg :self@0
          v40:BasicObject = LoadArg :k1@1
          v41:BasicObject = LoadArg :k2@2
          v42:BasicObject = LoadArg :k3@3
          v43:BasicObject = LoadArg :k4@4
          v44:BasicObject = LoadArg :k5@5
          v45:BasicObject = LoadArg :k6@6
          v46:BasicObject = LoadArg :k7@7
          v47:BasicObject = LoadArg :k8@8
          v48:BasicObject = LoadArg :k9@9
          v49:BasicObject = LoadArg :k10@10
          v50:BasicObject = LoadArg :k11@11
          v51:BasicObject = LoadArg :k12@12
          v52:BasicObject = LoadArg :k13@13
          v53:BasicObject = LoadArg :k14@14
          v54:BasicObject = LoadArg :k15@15
          v55:BasicObject = LoadArg :k16@16
          v56:BasicObject = LoadArg :k17@17
          v57:BasicObject = LoadArg :k18@18
          v58:BasicObject = LoadArg :k19@19
          v59:BasicObject = LoadArg :k20@20
          v60:BasicObject = LoadArg :k21@21
          v61:BasicObject = LoadArg :k22@22
          v62:BasicObject = LoadArg :k23@23
          v63:BasicObject = LoadArg :k24@24
          v64:BasicObject = LoadArg :k25@25
          v65:BasicObject = LoadArg :k26@26
          v66:BasicObject = LoadArg :k27@27
          v67:BasicObject = LoadArg :k28@28
          v68:BasicObject = LoadArg :k29@29
          v69:BasicObject = LoadArg :k30@30
          v70:BasicObject = LoadArg :k31@31
          v71:BasicObject = LoadArg :k32@32
          v72:BasicObject = LoadArg :k33@33
          v73:CPtr = GetEP 0
          v74:BasicObject = LoadField v73, :<empty>@0x1022
          Jump bb3(v39, v40, v41, v42, v43, v44, v45, v46, v47, v48, v49, v50, v51, v52, v53, v54, v55, v56, v57, v58, v59, v60, v61, v62, v63, v64, v65, v66, v67, v68, v69, v70, v71, v72, v74)
        bb3(v76:BasicObject, v77:BasicObject, v78:BasicObject, v79:BasicObject, v80:BasicObject, v81:BasicObject, v82:BasicObject, v83:BasicObject, v84:BasicObject, v85:BasicObject, v86:BasicObject, v87:BasicObject, v88:BasicObject, v89:BasicObject, v90:BasicObject, v91:BasicObject, v92:BasicObject, v93:BasicObject, v94:BasicObject, v95:BasicObject, v96:BasicObject, v97:BasicObject, v98:BasicObject, v99:BasicObject, v100:BasicObject, v101:BasicObject, v102:BasicObject, v103:BasicObject, v104:BasicObject, v105:BasicObject, v106:BasicObject, v107:BasicObject, v108:BasicObject, v109:BasicObject, v110:BasicObject):
          SideExit TooManyKeywordParameters
        ");
    }

    #[test]
    fn test_array_each() {
        assert_snapshot!(hir_string_proc("Array.instance_method(:each)"), @r"
        fn each@<internal:array>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:BasicObject, v9:NilClass):
          v13:NilClass = Const Value(nil)
          v15:TrueClass|NilClass = Defined yield, v13
          v17:CBool = Test v15
          v18:NilClass = RefineType v15, Falsy
          IfFalse v17, bb4(v8, v9)
          v20:TrueClass = RefineType v15, Truthy
          Jump bb6(v8, v9)
        bb4(v23:BasicObject, v24:NilClass):
          v28:BasicObject = InvokeBuiltin <inline_expr>, v23
          Jump bb5(v23, v24, v28)
        bb5(v40:BasicObject, v41:NilClass, v42:BasicObject):
          CheckInterrupts
          Return v42
        bb6(v30:BasicObject, v31:NilClass):
          v35:Fixnum[0] = Const Value(0)
          Jump bb8(v30, v35)
        bb8(v48:BasicObject, v49:Fixnum):
          v52:BoolExact = InvokeBuiltin rb_jit_ary_at_end, v48, v49
          v54:CBool = Test v52
          v55:FalseClass = RefineType v52, Falsy
          IfFalse v54, bb7(v48, v49)
          v57:TrueClass = RefineType v52, Truthy
          v59:NilClass = Const Value(nil)
          CheckInterrupts
          Return v48
        bb7(v67:BasicObject, v68:Fixnum):
          v72:BasicObject = InvokeBuiltin rb_jit_ary_at, v67, v68
          v74:BasicObject = InvokeBlock, v72 # SendFallbackReason: Uncategorized(invokeblock)
          v78:Fixnum = InvokeBuiltin rb_jit_fixnum_inc, v67, v68
          PatchPoint NoEPEscape(each)
          Jump bb8(v67, v78)
        ");
    }
 }

 /// Test successor and predecessor set computations.
 #[cfg(test)]
 mod control_flow_info_tests {
     use super::*;

     fn edge(target: BlockId) -> BranchEdge {
         BranchEdge { target, args: vec![] }
     }

     #[test]
     fn test_linked_list() {
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb1)));
        function.push_insn(bb1, Insn::Jump(edge(bb2)));
        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);

        assert!(cfi.is_preceded_by(bb1, bb2));
        assert!(cfi.is_succeeded_by(bb2, bb1));
        assert!(cfi.predecessors(bb3).eq([bb2]));
     }

     #[test]
     fn test_diamond() {
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);

        let v1 = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::IfTrue { val: v1, target: edge(bb2)});
        function.push_insn(bb0, Insn::Jump(edge(bb1)));
        function.push_insn(bb1, Insn::Jump(edge(bb3)));
        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);

        assert!(cfi.is_preceded_by(bb2, bb3));
        assert!(cfi.is_preceded_by(bb1, bb3));
        assert!(!cfi.is_preceded_by(bb0, bb3));
        assert!(cfi.is_succeeded_by(bb1, bb0));
        assert!(cfi.is_succeeded_by(bb3, bb1));
     }

     #[test]
     fn test_cfi_deduplicated_successors_and_predecessors() {
         let mut function = Function::new(std::ptr::null());

         let bb0 = function.entry_block;
         let bb1 = function.new_block(0);

         // Construct two separate jump instructions.
         let v1 = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
         let _ = function.push_insn(bb0, Insn::IfTrue { val: v1, target: edge(bb1)});
         function.push_insn(bb0, Insn::Jump(edge(bb1)));

         let retval = function.push_insn(bb1, Insn::Const { val: Const::CBool(true) });
         function.push_insn(bb1, Insn::Return { val: retval });

         function.seal_entries();
         let cfi = ControlFlowInfo::new(&function);

         assert_eq!(cfi.predecessors(bb1).collect::<Vec<_>>().len(), 1);
         assert_eq!(cfi.successors(bb0).collect::<Vec<_>>().len(), 1);
     }
 }

 /// Test dominator set computations.
 #[cfg(test)]
 mod dom_tests {
     use super::*;
     use insta::assert_snapshot;

     fn edge(target: BlockId) -> BranchEdge {
         BranchEdge { target, args: vec![] }
     }

     fn assert_dominators_contains_self(function: &Function, dominators: &Dominators) {
         for (i, _) in function.blocks.iter().enumerate() {
             // Ensure that each dominating set contains the block itself.
             assert!(dominators.is_dominated_by(BlockId(i), BlockId(i)));
         }
     }

     #[test]
     fn test_linked_list() {
         let mut function = Function::new(std::ptr::null());

         let entries = function.entries_block;
         let bb0 = function.entry_block;
         let bb1 = function.new_block(0);
         let bb2 = function.new_block(0);
         let bb3 = function.new_block(0);

         function.push_insn(bb0, Insn::Jump(edge(bb1)));
         function.push_insn(bb1, Insn::Jump(edge(bb2)));
         function.push_insn(bb2, Insn::Jump(edge(bb3)));

         let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
         function.push_insn(bb3, Insn::Return { val: retval });

         function.seal_entries();
         assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
         fn <manual>:
         bb1():
           Jump bb2()
         bb2():
           Jump bb3()
         bb3():
           Jump bb4()
         bb4():
           v3:Any = Const CBool(true)
           Return v3
         ");

         let dominators = Dominators::new(&function);
         assert_dominators_contains_self(&function, &dominators);
         assert_eq!(dominators.dominators(bb0), vec![entries, bb0]);
         assert_eq!(dominators.dominators(bb1), vec![entries, bb0, bb1]);
         assert_eq!(dominators.dominators(bb2), vec![entries, bb0, bb1, bb2]);
         assert_eq!(dominators.dominators(bb3), vec![entries, bb0, bb1, bb2, bb3]);
     }

     #[test]
     fn test_diamond() {
        let mut function = Function::new(std::ptr::null());

        let entries = function.entries_block;
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);

        let val = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::IfTrue { val, target: edge(bb1)});
        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        function.push_insn(bb2, Insn::Jump(edge(bb3)));
        function.push_insn(bb1, Insn::Jump(edge(bb3)));

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          IfTrue v0, bb2()
          Jump bb3()
        bb2():
          Jump bb4()
        bb3():
          Jump bb4()
        bb4():
          v5:Any = Const CBool(true)
          Return v5
        ");

        let dominators = Dominators::new(&function);
        assert_dominators_contains_self(&function, &dominators);
        assert_eq!(dominators.dominators(bb0), vec![entries, bb0]);
        assert_eq!(dominators.dominators(bb1), vec![entries, bb0, bb1]);
        assert_eq!(dominators.dominators(bb2), vec![entries, bb0, bb2]);
        assert_eq!(dominators.dominators(bb3), vec![entries, bb0, bb3]);
     }

    #[test]
    fn test_complex_cfg() {
        let mut function = Function::new(std::ptr::null());

        let entries = function.entries_block;
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);
        let bb4 = function.new_block(0);
        let bb5 = function.new_block(0);
        let bb6 = function.new_block(0);
        let bb7 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb1)));

        let v0 = function.push_insn(bb1, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb1, Insn::IfTrue { val: v0, target: edge(bb2)});
        function.push_insn(bb1, Insn::Jump(edge(bb4)));

        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        let v1 = function.push_insn(bb3, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb3, Insn::IfTrue { val: v1, target: edge(bb5)});
        function.push_insn(bb3, Insn::Jump(edge(bb7)));

        function.push_insn(bb4, Insn::Jump(edge(bb5)));

        function.push_insn(bb5, Insn::Jump(edge(bb6)));

        function.push_insn(bb6, Insn::Jump(edge(bb7)));

        let retval = function.push_insn(bb7, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb7, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          Jump bb2()
        bb2():
          v1:Any = Const Value(false)
          IfTrue v1, bb3()
          Jump bb5()
        bb3():
          Jump bb4()
        bb4():
          v5:Any = Const Value(false)
          IfTrue v5, bb6()
          Jump bb8()
        bb5():
          Jump bb6()
        bb6():
          Jump bb7()
        bb7():
          Jump bb8()
        bb8():
          v11:Any = Const CBool(true)
          Return v11
        ");

        let dominators = Dominators::new(&function);
        assert_dominators_contains_self(&function, &dominators);
        assert_eq!(dominators.dominators(bb0), vec![entries, bb0]);
        assert_eq!(dominators.dominators(bb1), vec![entries, bb0, bb1]);
        assert_eq!(dominators.dominators(bb2), vec![entries, bb0, bb1, bb2]);
        assert_eq!(dominators.dominators(bb3), vec![entries, bb0, bb1, bb2, bb3]);
        assert_eq!(dominators.dominators(bb4), vec![entries, bb0, bb1, bb4]);
        assert_eq!(dominators.dominators(bb5), vec![entries, bb0, bb1, bb5]);
        assert_eq!(dominators.dominators(bb6), vec![entries, bb0, bb1, bb5, bb6]);
        assert_eq!(dominators.dominators(bb7), vec![entries, bb0, bb1, bb7]);
    }

    #[test]
    fn test_back_edges() {
        let mut function = Function::new(std::ptr::null());

        let entries = function.entries_block;
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);
        let bb4 = function.new_block(0);
        let bb5 = function.new_block(0);

        let v0 = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::IfTrue { val: v0, target: edge(bb1)});
        function.push_insn(bb0, Insn::Jump(edge(bb4)));

        let v1 = function.push_insn(bb1, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb1, Insn::IfTrue { val: v1, target: edge(bb2)});
        function.push_insn(bb1, Insn::Jump(edge(bb3)));

        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        function.push_insn(bb4, Insn::Jump(edge(bb5)));

        let v2 = function.push_insn(bb5, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb5, Insn::IfTrue { val: v2, target: edge(bb3)});
        function.push_insn(bb5, Insn::Jump(edge(bb4)));

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          IfTrue v0, bb2()
          Jump bb5()
        bb2():
          v3:Any = Const Value(false)
          IfTrue v3, bb3()
          Jump bb4()
        bb3():
          Jump bb4()
        bb5():
          Jump bb6()
        bb6():
          v8:Any = Const Value(false)
          IfTrue v8, bb4()
          Jump bb5()
        bb4():
          v11:Any = Const CBool(true)
          Return v11
        ");

        let dominators = Dominators::new(&function);
        assert_dominators_contains_self(&function, &dominators);
        assert_eq!(dominators.dominators(bb0), vec![entries, bb0]);
        assert_eq!(dominators.dominators(bb1), vec![entries, bb0, bb1]);
        assert_eq!(dominators.dominators(bb2), vec![entries, bb0, bb1, bb2]);
        assert_eq!(dominators.dominators(bb3), vec![entries, bb0, bb3]);
        assert_eq!(dominators.dominators(bb4), vec![entries, bb0, bb4]);
        assert_eq!(dominators.dominators(bb5), vec![entries, bb0, bb4, bb5]);
    }

    #[test]
    fn test_multiple_entry_blocks() {
        let mut function = Function::new(std::ptr::null());

        let entries = function.entries_block;
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        function.jit_entry_blocks.push(bb1);
        let bb2 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let retval = function.push_insn(bb2, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb2, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          Jump bb3()
        bb2():
          Jump bb3()
        bb3():
          v2:Any = Const CBool(true)
          Return v2
        ");

        let dominators = Dominators::new(&function);
        assert_dominators_contains_self(&function, &dominators);

        assert_eq!(dominators.dominators(bb0), vec![entries, bb0]);
        assert_eq!(dominators.dominators(bb1), vec![entries, bb1]);
        assert_eq!(dominators.dominators(bb2), vec![entries, bb2]);

        assert!(!dominators.is_dominated_by(bb1, bb2));
    }
 }

 /// Test loop information computation.
#[cfg(test)]
mod loop_info_tests {
    use super::*;
    use insta::assert_snapshot;

    fn edge(target: BlockId) -> BranchEdge {
        BranchEdge { target, args: vec![] }
    }

    #[test]
    fn test_loop_depth() {
        // ┌─────┐
        // │ bb0 │
        // └──┬──┘
        //    │
        // ┌──▼──┐      ┌─────┐
        // │ bb2 ◄──────┼ bb1 ◄─┐
        // └──┬──┘      └─────┘ │
        //    └─────────────────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        let val = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb2, Insn::IfTrue { val, target: edge(bb1)});
        let retval = function.push_insn(bb2, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb2, Insn::Return { val: retval });

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          Jump bb3()
          v1:Any = Const Value(false)
        bb3():
          IfTrue v1, bb2()
          v3:Any = Const CBool(true)
          Return v3
        bb2():
          Jump bb3()
        ");

        assert!(loop_info.is_loop_header(bb2));
        assert!(loop_info.is_back_edge_source(bb1));
        assert_eq!(loop_info.loop_depth(bb1), 1);
    }

    #[test]
    fn test_nested_loops() {
        // ┌─────┐
        // │ bb0 ◄─────┐
        // └──┬──┘     │
        //    │        │
        // ┌──▼──┐     │
        // │ bb1 ◄───┐ │
        // └──┬──┘   │ │
        //    │      │ │
        // ┌──▼──┐   │ │
        // │ bb2 ┼───┘ │
        // └──┬──┘     │
        //    │        │
        // ┌──▼──┐     │
        // │ bb3 ┼─────┘
        // └──┬──┘
        //    │
        // ┌──▼──┐
        // │ bb4 │
        // └─────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);
        let bb4 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb1)));

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let cond = function.push_insn(bb2, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb2, Insn::IfTrue { val: cond, target: edge(bb1) });
        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        let cond = function.push_insn(bb3, Insn::Const { val: Const::Value(Qtrue) });
        let _ = function.push_insn(bb3, Insn::IfTrue { val: cond, target: edge(bb0) });
        function.push_insn(bb3, Insn::Jump(edge(bb4)));

        let retval = function.push_insn(bb4, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb4, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          Jump bb2()
        bb2():
          Jump bb3()
        bb3():
          v2:Any = Const Value(false)
          IfTrue v2, bb2()
          Jump bb4()
        bb4():
          v5:Any = Const Value(true)
          IfTrue v5, bb1()
          Jump bb5()
        bb5():
          v8:Any = Const CBool(true)
          Return v8
        ");

        assert!(loop_info.is_loop_header(bb0));
        assert!(loop_info.is_loop_header(bb1));

        assert_eq!(loop_info.loop_depth(bb0), 1);
        assert_eq!(loop_info.loop_depth(bb1), 2);
        assert_eq!(loop_info.loop_depth(bb2), 2);
        assert_eq!(loop_info.loop_depth(bb3), 1);
        assert_eq!(loop_info.loop_depth(bb4), 0);

        assert!(loop_info.is_back_edge_source(bb2));
        assert!(loop_info.is_back_edge_source(bb3));
    }

    #[test]
    fn test_complex_loops() {
        //        ┌─────┐
        // ┌──────► bb0 │
        // │      └──┬──┘
        // │    ┌────┴────┐
        // │ ┌──▼──┐   ┌──▼──┐
        // │ │ bb1 ◄─┐ │ bb3 ◄─┐
        // │ └──┬──┘ │ └──┬──┘ │
        // │    │    │    │    │
        // │ ┌──▼──┐ │ ┌──▼──┐ │
        // │ │ bb2 ┼─┘ │ bb4 ┼─┘
        // │ └──┬──┘   └──┬──┘
        // │    └────┬────┘
        // │      ┌──▼──┐
        // └──────┼ bb5 │
        //        └──┬──┘
        //           │
        //        ┌──▼──┐
        //        │ bb6 │
        //        └─────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);
        let bb4 = function.new_block(0);
        let bb5 = function.new_block(0);
        let bb6 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::IfTrue { val: cond, target: edge(bb1) });
        function.push_insn(bb0, Insn::Jump(edge(bb3)));

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let _ = function.push_insn(bb2, Insn::IfTrue { val: cond, target: edge(bb1) });
        function.push_insn(bb2, Insn::Jump(edge(bb5)));

        function.push_insn(bb3, Insn::Jump(edge(bb4)));

        let _ = function.push_insn(bb4, Insn::IfTrue { val: cond, target: edge(bb3) });
        function.push_insn(bb4, Insn::Jump(edge(bb5)));

        let _ = function.push_insn(bb5, Insn::IfTrue { val: cond, target: edge(bb0) });
        function.push_insn(bb5, Insn::Jump(edge(bb6)));

        let retval = function.push_insn(bb6, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb6, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          IfTrue v0, bb2()
          Jump bb4()
        bb2():
          Jump bb3()
        bb3():
          IfTrue v0, bb2()
          Jump bb6()
        bb4():
          Jump bb5()
        bb5():
          IfTrue v0, bb4()
          Jump bb6()
        bb6():
          IfTrue v0, bb1()
          Jump bb7()
        bb7():
          v11:Any = Const CBool(true)
          Return v11
        ");

        assert!(loop_info.is_loop_header(bb0));
        assert!(loop_info.is_loop_header(bb1));
        assert!(!loop_info.is_loop_header(bb2));
        assert!(loop_info.is_loop_header(bb3));
        assert!(!loop_info.is_loop_header(bb5));
        assert!(!loop_info.is_loop_header(bb4));
        assert!(!loop_info.is_loop_header(bb6));

        assert_eq!(loop_info.loop_depth(bb0), 1);
        assert_eq!(loop_info.loop_depth(bb1), 2);
        assert_eq!(loop_info.loop_depth(bb2), 2);
        assert_eq!(loop_info.loop_depth(bb3), 2);
        assert_eq!(loop_info.loop_depth(bb4), 2);
        assert_eq!(loop_info.loop_depth(bb5), 1);
        assert_eq!(loop_info.loop_depth(bb6), 0);

        assert!(loop_info.is_back_edge_source(bb2));
        assert!(loop_info.is_back_edge_source(bb4));
        assert!(loop_info.is_back_edge_source(bb5));
    }

    #[test]
    fn linked_list_non_loop() {
        // ┌─────┐
        // │ bb0 │
        // └──┬──┘
        //    │
        // ┌──▼──┐
        // │ bb1 │
        // └──┬──┘
        //    │
        // ┌──▼──┐
        // │ bb2 │
        // └─────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        let _ = function.push_insn(bb0, Insn::Jump(edge(bb1)));
        let _ = function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let retval = function.push_insn(bb2, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb2, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          Jump bb2()
        bb2():
          Jump bb3()
        bb3():
          v2:Any = Const CBool(true)
          Return v2
        ");

        assert!(!loop_info.is_loop_header(bb0));
        assert!(!loop_info.is_loop_header(bb1));
        assert!(!loop_info.is_loop_header(bb2));

        assert!(!loop_info.is_back_edge_source(bb0));
        assert!(!loop_info.is_back_edge_source(bb1));
        assert!(!loop_info.is_back_edge_source(bb2));

        assert_eq!(loop_info.loop_depth(bb0), 0);
        assert_eq!(loop_info.loop_depth(bb1), 0);
        assert_eq!(loop_info.loop_depth(bb2), 0);
    }

    #[test]
    fn triple_nested_loop() {
        // ┌─────┐
        // │ bb0 ◄──┐
        // └──┬──┘  │
        //    │     │
        // ┌──▼──┐  │
        // │ bb1 ◄─┐│
        // └──┬──┘ ││
        //    │    ││
        // ┌──▼──┐ ││
        // │ bb2 ◄┐││
        // └──┬──┘│││
        //    │   │││
        // ┌──▼──┐│││
        // │ bb3 ┼┘││
        // └──┬──┘ ││
        //    │    ││
        // ┌──▼──┐ ││
        // │ bb4 ┼─┘│
        // └──┬──┘  │
        //    │     │
        // ┌──▼──┐  │
        // │ bb5 ┼──┘
        // └─────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);
        let bb4 = function.new_block(0);
        let bb5 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::Jump(edge(bb1)));
        let _ = function.push_insn(bb1, Insn::Jump(edge(bb2)));
        let _ = function.push_insn(bb2, Insn::Jump(edge(bb3)));
        let _ = function.push_insn(bb3, Insn::Jump(edge(bb4)));
        let _ = function.push_insn(bb3, Insn::IfTrue {val: cond, target: edge(bb2)});
        let _ = function.push_insn(bb4, Insn::Jump(edge(bb5)));
        let _ = function.push_insn(bb4, Insn::IfTrue {val: cond, target: edge(bb1)});
        let _ = function.push_insn(bb5, Insn::IfTrue {val: cond, target: edge(bb0)});

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @r"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          Jump bb2()
        bb2():
          Jump bb3()
        bb3():
          Jump bb4()
        bb4():
          Jump bb5()
          IfTrue v0, bb3()
        bb5():
          Jump bb6()
          IfTrue v0, bb2()
        bb6():
          IfTrue v0, bb1()
        ");

        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert!(!loop_info.is_back_edge_source(bb0));
        assert!(!loop_info.is_back_edge_source(bb1));
        assert!(!loop_info.is_back_edge_source(bb2));
        assert!(loop_info.is_back_edge_source(bb3));
        assert!(loop_info.is_back_edge_source(bb4));
        assert!(loop_info.is_back_edge_source(bb5));

        assert_eq!(loop_info.loop_depth(bb0), 1);
        assert_eq!(loop_info.loop_depth(bb1), 2);
        assert_eq!(loop_info.loop_depth(bb2), 3);
        assert_eq!(loop_info.loop_depth(bb3), 3);
        assert_eq!(loop_info.loop_depth(bb4), 2);
        assert_eq!(loop_info.loop_depth(bb5), 1);

        assert!(loop_info.is_loop_header(bb0));
        assert!(loop_info.is_loop_header(bb1));
        assert!(loop_info.is_loop_header(bb2));
        assert!(!loop_info.is_loop_header(bb3));
        assert!(!loop_info.is_loop_header(bb4));
        assert!(!loop_info.is_loop_header(bb5));
    }
 }

/// Test dumping to iongraph format.
#[cfg(test)]
mod iongraph_tests {
    use super::*;
    use insta::assert_snapshot;

    fn edge(target: BlockId) -> BranchEdge {
        BranchEdge { target, args: vec![] }
    }

    #[test]
    fn test_simple_function() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;

        let retval = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::Return { val: retval });

        let json = function.to_iongraph_pass("simple");
        assert_snapshot!(json.to_string(), @r#"{"name":"simple", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_two_blocks() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb1)));

        let retval = function.push_insn(bb1, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb1, Insn::Return { val: retval });

        let json = function.to_iongraph_pass("two_blocks");
        assert_snapshot!(json.to_string(), @r#"{"name":"two_blocks", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_multiple_instructions() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;

        let val1 = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::Return { val: val1 });

        let json = function.to_iongraph_pass("multiple_instructions");
        assert_snapshot!(json.to_string(), @r#"{"name":"multiple_instructions", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_conditional_branch() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::IfTrue { val: cond, target: edge(bb1) });

        let retval1 = function.push_insn(bb0, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb0, Insn::Return { val: retval1 });

        let retval2 = function.push_insn(bb1, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb1, Insn::Return { val: retval2 });

        let json = function.to_iongraph_pass("conditional_branch");
        assert_snapshot!(json.to_string(), @r#"{"name":"conditional_branch", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_loop_structure() {
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        let val = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb2, Insn::IfTrue { val, target: edge(bb1)});
        let retval = function.push_insn(bb2, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb2, Insn::Return { val: retval });

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let json = function.to_iongraph_pass("loop_structure");
        assert_snapshot!(json.to_string(), @r#"{"name":"loop_structure", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_multiple_successors() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::IfTrue { val: cond, target: edge(bb1) });
        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        let retval1 = function.push_insn(bb1, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb1, Insn::Return { val: retval1 });

        let retval2 = function.push_insn(bb2, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb2, Insn::Return { val: retval2 });

        let json = function.to_iongraph_pass("multiple_successors");
        assert_snapshot!(json.to_string(), @r#"{"name":"multiple_successors", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[], "instructions":[]}]}, "lir":{"blocks":[]}}"#);
    }
 }
