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
        assert_snapshot!(optimized_hir_string("test"), @"
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
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [] }
          PatchPoint NoTracePoint
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          v13:Any = Snapshot FrameState { pc: 0x1008, stack: [v10, v12] }
          PatchPoint MethodRedefined(Integer@0x1010, +@0x1018, cme:0x1020)
          v35:Fixnum[6] = Const Value(6)
          v21:Any = Snapshot FrameState { pc: 0x1048, stack: [v35] }
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v12:Any = Snapshot FrameState { pc: 0x1008, stack: [] }
          v13:Any = Snapshot FrameState { pc: 0x1010, stack: [] }
          PatchPoint NoTracePoint
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v17:Any = Snapshot FrameState { pc: 0x1018, stack: [v16] }
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v20:Any = Snapshot FrameState { pc: 0x1020, stack: [v16, v19] }
          v21:ArrayExact = NewArray v16, v19
          v22:Any = Snapshot FrameState { pc: 0x1028, stack: [v21] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v21
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
        assert_snapshot!(optimized_hir_string("test"), @"
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
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[1] = Const Value(1)
          v15:Fixnum[2] = Const Value(2)
          v16:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13, v15] }
          v23:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v13, v15, v11] }
          PatchPoint MethodRedefined(Object@0x1010, foo@0x1018, cme:0x1020)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1010)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1010)]
          v26:BasicObject = SendDirect v25, 0x1048, :foo (0x1058), v13, v15, v11
          v18:Any = Snapshot FrameState { pc: 0x1060, stack: [v26] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v26
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
        assert_snapshot!(optimized_hir_string("test"), @"
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
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          v14:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13] }
          PatchPoint MethodRedefined(Object@0x1010, foo@0x1018, cme:0x1020)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1010)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1010)]
          v23:BasicObject = SendDirect v22, 0x1048, :foo (0x1058), v11, v13
          v16:Any = Snapshot FrameState { pc: 0x1060, stack: [v23] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v23
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
        assert_snapshot!(optimized_hir_string("test"), @"
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
          v8:Any = Snapshot FrameState { pc: 0x1000, stack: [] }
          PatchPoint NoTracePoint
          v11:Fixnum[5] = Const Value(5)
          v13:Fixnum[6] = Const Value(6)
          v15:Fixnum[4] = Const Value(4)
          v17:Fixnum[3] = Const Value(3)
          v19:Fixnum[1] = Const Value(1)
          v21:Fixnum[2] = Const Value(2)
          v23:Fixnum[7] = Const Value(7)
          v25:Fixnum[8] = Const Value(8)
          v26:Any = Snapshot FrameState { pc: 0x1008, stack: [v6, v11, v13, v15, v17, v19, v21, v23, v25] }
          v27:BasicObject = Send v6, :foo, v11, v13, v15, v17, v19, v21, v23, v25 # SendFallbackReason: Too many arguments for LIR
          v28:Any = Snapshot FrameState { pc: 0x1010, stack: [v27] }
          PatchPoint NoTracePoint
          CheckInterrupts
          Return v27
        ");
    }
}

#[cfg(test)]
pub(crate) mod hir_build_tests {
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
    pub fn assert_compile_fails(method: &str, reason: ParseError) {
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
          v2:CPtr = LoadPC
          v3:CPtr[CPtr(0x1000)] = Const CPtr(0x1000)
          v4:CBool = IsBitEqual v2, v3
          CondBranch v4, bb3(v1), bb6()
        bb6():
          Jump bb5(v1)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:NilClass = Const Value(nil)
          v10:CPtr = GetEP 0
          StoreField v10, :x@0x1001, v9
          Jump bb3(v8)
        bb3(v19:BasicObject):
          v22:Fixnum[1] = Const Value(1)
          SetLocal :x, l0, EP@3, v22
          Jump bb5(v19)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :x@1
          v16:CPtr = GetEP 0
          StoreField v16, :x@0x1001, v15
          Jump bb5(v14)
        bb5(v26:BasicObject):
          v30:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_putobject() {
        eval("def test = 123");
        assert_contains_opcode("test", YARVINSN_putobject);
        assert_snapshot!(hir_string("test"), @"
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
    fn test_checkmatch_case() {
        eval(r#"
            def test(o)
              case o
              in Integer
                1
              else
                2
              end
            end
            test(1)
        "#);
        assert_contains_opcode("test", YARVINSN_checkmatch);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :o@1
          v6:CPtr = GetEP 0
          StoreField v6, :o@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:NilClass = Const Value(nil)
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :o@0x1000
          v19:BasicObject = GetConstantPath 0x1008
          v21:BasicObject = CheckMatch v16, v19, CASE
          CheckInterrupts
          v24:CBool = Test v21
          v25:Truthy = RefineType v21, Truthy
          CondBranch v24, bb4(v9, v13, v16), bb5()
        bb4(v37:BasicObject, v38:NilClass, v39:BasicObject):
          v44:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v44
        bb5():
          v27:Falsy = RefineType v21, Falsy
          v32:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_checkmatch_case_splat_array() {
        eval(r#"
            def test(o)
              case o
              when *[1, 2]
                1
              else
                2
              end
            end
            test(1)
        "#);
        assert_contains_opcode("test", YARVINSN_checkmatch);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :o@1
          v6:CPtr = GetEP 0
          StoreField v6, :o@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :o@0x1000
          v17:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v18:ArrayExact = ArrayDup v17
          v20:BasicObject = CheckMatch v14, v18, CASE|ARRAY
          CheckInterrupts
          v23:CBool = Test v20
          v24:Truthy = RefineType v20, Truthy
          CondBranch v23, bb4(v9, v14), bb5()
        bb4(v35:BasicObject, v36:BasicObject):
          v41:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v41
        bb5():
          v26:Falsy = RefineType v20, Falsy
          v30:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_checkmatch_when_splat_array() {
        eval(r#"
            def test
              case
              when *[1, 2]
                1
              else
                2
              end
            end
            test
        "#);
        assert_contains_opcode("test", YARVINSN_checkmatch);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:ArrayExact = ArrayDup v12
          v15:BasicObject = CheckMatch v10, v13, WHEN|ARRAY
          CheckInterrupts
          v18:CBool = Test v15
          v19:Truthy = RefineType v15, Truthy
          CondBranch v18, bb4(v6), bb5()
        bb4(v29:BasicObject):
          v33:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v33
        bb5():
          v21:Falsy = RefineType v15, Falsy
          v24:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_new_array() {
        eval("def test = []");
        assert_contains_opcode("test", YARVINSN_newarray);
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:ArrayExact = NewArray v14
          CheckInterrupts
          Return v16
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v21:ArrayExact = NewArray v16, v19
          CheckInterrupts
          Return v21
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:Fixnum[10] = Const Value(10)
          v18:RangeExact = NewRange v14 NewRangeInclusive v16
          CheckInterrupts
          Return v18
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v21:RangeExact = NewRange v16 NewRangeInclusive v19
          CheckInterrupts
          Return v21
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:Fixnum[10] = Const Value(10)
          v18:RangeExact = NewRange v14 NewRangeExclusive v16
          CheckInterrupts
          Return v18
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v21:RangeExact = NewRange v16 NewRangeExclusive v19
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_array_dup() {
        eval("def test = [1, 2, 3]");
        assert_contains_opcode("test", YARVINSN_duparray);
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :aval@1
          v6:CPtr = GetEP 0
          StoreField v6, :aval@0x1000, v5
          v8:BasicObject = LoadArg :bval@2
          StoreField v6, :bval@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:StaticSymbol[:a] = Const Value(VALUE(0x1008))
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :aval@0x1000
          v20:StaticSymbol[:b] = Const Value(VALUE(0x1010))
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :bval@0x1001
          v25:HashExact = NewHash v15: v18, v20: v23
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_string_copy() {
        eval("def test = \"hello\"");
        assert_contains_opcode("test", YARVINSN_dupchilledstring);
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          SetLocal :a, l0, EP@3, v13
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :a@0x1000
          CheckInterrupts
          Return v19
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
        assert_snapshot!(hir_string("test"), @"
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
          v2:CPtr = LoadPC
          v3:CPtr[CPtr(0x1000)] = Const CPtr(0x1000)
          v4:CBool = IsBitEqual v2, v3
          CondBranch v4, bb3(v1), bb6()
        bb6():
          Jump bb5(v1)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:NilClass = Const Value(nil)
          v10:CPtr = GetEP 0
          StoreField v10, :a@0x1001, v9
          v12:NilClass = Const Value(nil)
          StoreField v10, :b@0x1002, v12
          Jump bb3(v8)
        bb3(v23:BasicObject):
          v27:Fixnum[1] = Const Value(1)
          SetLocal :b, l0, EP@3, v27
          SetLocal :a, l0, EP@4, v27
          Jump bb5(v23)
        bb4():
          EntryPoint JIT(1)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :a@1
          v18:CPtr = GetEP 0
          StoreField v18, :a@0x1001, v17
          v20:NilClass = Const Value(nil)
          StoreField v18, :b@0x1002, v20
          Jump bb5(v16)
        bb5(v34:BasicObject):
          v38:CPtr = GetEP 0
          v39:BasicObject = LoadField v38, :a@0x1001
          v41:CPtr = GetEP 0
          v42:BasicObject = LoadField v41, :b@0x1002
          v44:ArrayExact = NewArray v39, v42
          CheckInterrupts
          Return v44
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
          v2:CPtr = LoadPC
          v3:CPtr[CPtr(0x1000)] = Const CPtr(0x1000)
          v4:CBool = IsBitEqual v2, v3
          CondBranch v4, bb3(v1), bb6()
        bb6():
          Jump bb5(v1)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:NilClass = Const Value(nil)
          v10:CPtr = GetEP 0
          StoreField v10, :a@0x1001, v9
          v12:NilClass = Const Value(nil)
          StoreField v10, :b@0x1002, v12
          Jump bb3(v8)
        bb3(v23:BasicObject):
          SideExit UnhandledYARVInsn(trace_putobject_INT2FIX_1_)
        bb4():
          EntryPoint JIT(1)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :a@1
          v18:CPtr = GetEP 0
          StoreField v18, :a@0x1001, v17
          v20:NilClass = Const Value(nil)
          StoreField v18, :b@0x1002, v20
          Jump bb5(v16)
        bb5(v28:BasicObject):
          v32:CPtr = GetEP 0
          v33:BasicObject = LoadField v32, :a@0x1001
          v35:CPtr = GetEP 0
          v36:BasicObject = LoadField v35, :b@0x1002
          v38:ArrayExact = NewArray v33, v36
          CheckInterrupts
          Return v38
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
          v2:CPtr = LoadPC
          v3:CPtr[CPtr(0x1000)] = Const CPtr(0x1000)
          v4:CBool = IsBitEqual v2, v3
          CondBranch v4, bb3(v1), bb6()
        bb6():
          Jump bb5(v1)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:NilClass = Const Value(nil)
          v10:CPtr = GetEP 0
          StoreField v10, :a@0x1001, v9
          Jump bb3(v8)
        bb3(v19:BasicObject):
          SideExit UnhandledYARVInsn(definemethod)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :a@1
          v16:CPtr = GetEP 0
          StoreField v16, :a@0x1001, v15
          Jump bb5(v14)
        bb5(v24:BasicObject):
          v28:CPtr = GetEP 0
          v29:BasicObject = LoadField v28, :a@0x1001
          CheckInterrupts
          Return v29
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb4():
          EntryPoint JIT(1)
          v10:BasicObject = LoadArg :self@0
          v11:BasicObject = LoadArg :a@1
          v12:CPtr = GetEP 0
          StoreField v12, :a@0x1000, v11
          Jump bb3(v10)
        bb3(v15:BasicObject):
          v21:CPtr = GetEP 0
          v22:BasicObject = LoadField v21, :a@0x1000
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn defined_ivar() {
        eval("
            def test = defined?(@foo)
        ");
        assert_contains_opcode("test", YARVINSN_definedivar);
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          CondBranch v13, bb5(), bb4(v6)
        bb5():
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :cond@1
          v6:CPtr = GetEP 0
          StoreField v6, :cond@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :cond@0x1000
          CheckInterrupts
          v17:CBool = Test v14
          v18:Falsy = RefineType v14, Falsy
          CondBranch v17, bb5(), bb4(v9)
        bb5():
          v20:Truthy = RefineType v14, Truthy
          v23:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v23
        bb4(v28:BasicObject):
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :cond@1
          v6:CPtr = GetEP 0
          StoreField v6, :cond@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :result@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :cond@0x1000
          CheckInterrupts
          v19:CBool = Test v16
          v20:Falsy = RefineType v16, Falsy
          CondBranch v19, bb6(), bb4(v11)
        bb6():
          v22:Truthy = RefineType v16, Truthy
          v25:Fixnum[3] = Const Value(3)
          SetLocal :result, l0, EP@3, v25
          CheckInterrupts
          Jump bb5(v11)
        bb4(v31:BasicObject):
          v35:Fixnum[4] = Const Value(4)
          SetLocal :result, l0, EP@3, v35
          Jump bb5(v31)
        bb5(v39:BasicObject):
          v43:CPtr = GetEP 0
          v44:BasicObject = LoadField v43, :result@0x1001
          CheckInterrupts
          Return v44
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :+, v19 # SendFallbackReason: Uncategorized(opt_plus)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :-, v19 # SendFallbackReason: Uncategorized(opt_minus)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :*, v19 # SendFallbackReason: Uncategorized(opt_mult)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :/, v19 # SendFallbackReason: Uncategorized(opt_div)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :%, v19 # SendFallbackReason: Uncategorized(opt_mod)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :==, v19 # SendFallbackReason: Uncategorized(opt_eq)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :!=, v19 # SendFallbackReason: Uncategorized(opt_neq)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :<, v19 # SendFallbackReason: Uncategorized(opt_lt)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :<=, v19 # SendFallbackReason: Uncategorized(opt_le)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :>, v19 # SendFallbackReason: Uncategorized(opt_gt)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :result@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :times@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          SetLocal :result, l0, EP@4, v15
          v20:Fixnum[10] = Const Value(10)
          SetLocal :times, l0, EP@3, v20
          CheckInterrupts
          Jump bb5(v11)
        bb5(v27:BasicObject):
          v30:CPtr = GetEP 0
          v31:BasicObject = LoadField v30, :times@0x1001
          v33:Fixnum[0] = Const Value(0)
          v36:BasicObject = Send v31, :>, v33 # SendFallbackReason: Uncategorized(opt_gt)
          CheckInterrupts
          v39:CBool = Test v36
          v40:Truthy = RefineType v36, Truthy
          CondBranch v39, bb4(v27), bb6()
        bb4(v54:BasicObject):
          v58:CPtr = GetEP 0
          v59:BasicObject = LoadField v58, :result@0x1000
          v61:Fixnum[1] = Const Value(1)
          v64:BasicObject = Send v59, :+, v61 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :result, l0, EP@4, v64
          v69:CPtr = GetEP 0
          v70:BasicObject = LoadField v69, :times@0x1001
          v72:Fixnum[1] = Const Value(1)
          v75:BasicObject = Send v70, :-, v72 # SendFallbackReason: Uncategorized(opt_minus)
          SetLocal :times, l0, EP@3, v75
          Jump bb5(v54)
        bb6():
          v42:Falsy = RefineType v36, Falsy
          v44:NilClass = Const Value(nil)
          v48:CPtr = GetEP 0
          v49:BasicObject = LoadField v48, :result@0x1000
          CheckInterrupts
          Return v49
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :>=, v19 # SendFallbackReason: Uncategorized(opt_ge)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :cond@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:TrueClass = Const Value(true)
          SetLocal :cond, l0, EP@3, v13
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :cond@0x1000
          CheckInterrupts
          v22:CBool = Test v19
          v23:Falsy = RefineType v19, Falsy
          CondBranch v22, bb5(), bb4(v9)
        bb5():
          v25:Truthy = RefineType v19, Truthy
          v28:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v28
        bb4(v33:BasicObject):
          v37:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v37
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:BasicObject = Send v14, 0x1008, :each # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v16
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :a@0x1000
          v17:ArrayExact = ToArray v15
          v19:BasicObject = Send v9, :foo, v17 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v19
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :a@0x1000
          v17:BasicObject = Send v9, &block, :foo, v15 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:Fixnum[1] = Const Value(1)
          v16:BasicObject = Send v9, :foo, v14 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v16
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :a@0x1000
          v17:BasicObject = Send v9, :foo, v15 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v17
        ");
    }

    // TODO(max): Figure out how to generate a call with TAILCALL flag

    #[test]
    fn test_compile_super() {
        eval("
            def test = super()
        ");
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :...@0x1000
          v17:BasicObject = InvokeSuperForward v9, 0x1008, v15 # SendFallbackReason: InvokeSuperForward: not yet specialized
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :...@0x1000
          v17:BasicObject = InvokeSuperForward v9, 0x1008, v15 # SendFallbackReason: InvokeSuperForward: not yet specialized
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :...@0x1000
          v17:BasicObject = InvokeSuperForward v9, 0x1008, v15 # SendFallbackReason: InvokeSuperForward: not yet specialized
          v19:Fixnum[1] = Const Value(1)
          v22:BasicObject = Send v17, :+, v19 # SendFallbackReason: Uncategorized(opt_plus)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:Fixnum[1] = Const Value(1)
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :...@0x1000
          v19:BasicObject = InvokeSuperForward v9, 0x1008, v14, v17 # SendFallbackReason: InvokeSuperForward: not yet specialized
          CheckInterrupts
          Return v19
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          Return v13
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:ClassSubclass[VMFrozenCore] = Const Value(VALUE(0x1008))
          v16:HashExact = NewHash
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :a@0x1000
          v21:BasicObject = Send v14, :core#hash_merge_kwd, v16, v19 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v23:ClassSubclass[VMFrozenCore] = Const Value(VALUE(0x1008))
          v26:StaticSymbol[:b] = Const Value(VALUE(0x1010))
          v28:Fixnum[1] = Const Value(1)
          v30:BasicObject = Send v23, :core#hash_merge_ptr, v21, v26, v28 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v32:BasicObject = Send v9, :foo, v30 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v32
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :*@1
          v6:CPtr = GetEP 0
          StoreField v6, :*@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :*@0x1000
          v17:ArrayExact = ToNewArray v15
          v19:Fixnum[1] = Const Value(1)
          v21:CUInt64 = LoadField v17, :RBASIC_FLAGS@0x1001
          v22:CUInt64 = GuardNoBitsSet v21, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v17, v19
          v25:BasicObject = Send v9, :foo, v17 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v25
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :...@1
          v6:CPtr = GetEP 0
          StoreField v6, :...@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:BasicObject = LoadField v14, :...@0x1000
          v17:BasicObject = SendForward v9, 0x1008, :foo, v15 # SendFallbackReason: SendForward: not yet specialized
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :*@2
          StoreField v6, :*@0x1001, v8
          v10:BasicObject = LoadArg :**@3
          StoreField v6, :**@0x1002, v10
          v12:BasicObject = LoadArg :&@4
          StoreField v6, :&@0x1003, v12
          v14:NilClass = Const Value(nil)
          StoreField v6, :...@0x1004, v14
          Jump bb3(v4)
        bb3(v17:BasicObject):
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :a@0x1000
          v25:CPtr = GetEP 0
          v26:BasicObject = LoadField v25, :*@0x1001
          v28:ArrayExact = ToArray v26
          v30:CPtr = GetEP 0
          v31:BasicObject = LoadField v30, :**@0x1002
          v34:CPtr = GetEP 0
          v35:CUInt64 = LoadField v34, :VM_ENV_DATA_INDEX_FLAGS@0x1005
          v36:CBool = IsBlockParamModified v35
          CondBranch v36, bb4(), bb5()
        bb4():
          v38:BasicObject = LoadField v34, :&@0x1003
          Jump bb6(v38)
        bb5():
          v40:CInt64 = LoadField v34, :VM_ENV_DATA_INDEX_SPECVAL@0x1006
          v41:CInt64 = GuardAnyBitSet v40, CUInt64(1)
          v42:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v42)
        bb6(v33:BasicObject):
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
        assert_snapshot!(hir_string("test"), @"
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
          CondBranch v15, bb6(), bb4(v6, v12, v10)
        bb6():
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX)
          v22:BasicObject = ArrayMax v16, v19
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX))
        ");
    }

    #[test]
    fn test_opt_newarray_send_min_no_elements() {
        eval("
            def test = [].min
        ");
        // TODO(max): Rewrite to nil
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
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
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MIN)
          v11:BasicObject = ArrayMin
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_opt_newarray_send_min() {
        eval("
            def test(a,b) = [a,b].min
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MIN)
          v22:BasicObject = ArrayMin v16, v19
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_opt_newarray_send_min_redefined() {
        eval("
            class Array
              alias_method :old_min, :min
              def min
                old_min * 2
              end
            end

            def test(a,b) = [a,b].min
        ");
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MIN))
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_HASH)
          v38:Fixnum = ArrayHash v32, v35
          SetLocal :result, l0, EP@3, v38
          v44:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v45:ArrayExact = ArrayDup v44
          v47:BasicObject = Send v15, :puts, v45 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v51:CPtr = GetEP 0
          v52:BasicObject = LoadField v51, :result@0x1003
          CheckInterrupts
          Return v52
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
          v37:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v38:StringExact = StringCopy v37
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_PACK)
          v41:String = ArrayPackBuffer v32, v35, fmt: v38
          SetLocal :result, l0, EP@3, v41
          v47:ArrayExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v48:ArrayExact = ArrayDup v47
          v50:BasicObject = Send v15, :puts, v48 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v54:CPtr = GetEP 0
          v55:BasicObject = LoadField v54, :result@0x1003
          CheckInterrupts
          Return v55
        ");
    }

    #[test]
    fn test_opt_newarray_send_pack_redefined() {
        eval(r#"
            class Array
              def pack(fmt, buffer: nil) = 5
            end
            def test(a,b)
              sum = a+b
              result = [a,b].pack 'C'
              puts [1,2,3]
              result
            end
        "#);
        assert_contains_opcode("test", YARVINSN_opt_newarray_send);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
          v37:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v38:StringExact = StringCopy v37
          SideExit PatchPoint(BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_PACK))
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :buf@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v32:StringExact = StringCopy v31
          SetLocal :buf, l0, EP@3, v32
          v37:CPtr = GetEP 0
          v38:BasicObject = LoadField v37, :a@0x1000
          v40:CPtr = GetEP 0
          v41:BasicObject = LoadField v40, :b@0x1001
          v43:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v44:StringExact = StringCopy v43
          v46:CPtr = GetEP 0
          v47:BasicObject = LoadField v46, :buf@0x1003
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_PACK)
          v50:String = ArrayPackBuffer v38, v41, fmt: v44, buf: v47
          v54:CPtr = GetEP 0
          v55:BasicObject = LoadField v54, :buf@0x1003
          CheckInterrupts
          Return v55
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :buf@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v32:StringExact = StringCopy v31
          SetLocal :buf, l0, EP@3, v32
          v37:CPtr = GetEP 0
          v38:BasicObject = LoadField v37, :a@0x1000
          v40:CPtr = GetEP 0
          v41:BasicObject = LoadField v40, :b@0x1001
          v43:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v44:StringExact = StringCopy v43
          v46:CPtr = GetEP 0
          v47:BasicObject = LoadField v46, :buf@0x1003
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
          v37:CPtr = GetEP 0
          v38:BasicObject = LoadField v37, :b@0x1001
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P)
          v41:BoolExact = ArrayInclude v32, v35 | v38
          SetLocal :result, l0, EP@3, v41
          v47:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v48:ArrayExact = ArrayDup v47
          v50:BasicObject = Send v15, :puts, v48 # SendFallbackReason: Uncategorized(opt_send_without_block)
          v54:CPtr = GetEP 0
          v55:BasicObject = LoadField v54, :result@0x1003
          CheckInterrupts
          Return v55
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :sum@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :result@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1000
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :b@0x1001
          v26:BasicObject = Send v20, :+, v23 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :sum, l0, EP@4, v26
          v31:CPtr = GetEP 0
          v32:BasicObject = LoadField v31, :a@0x1000
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :b@0x1001
          v37:CPtr = GetEP 0
          v38:BasicObject = LoadField v37, :b@0x1001
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_INCLUDE_P)
          v17:BoolExact = DupArrayInclude VALUE(0x1008) | v14
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v21:ArrayExact = NewArray v16, v19
          v24:BasicObject = Send v21, :length # SendFallbackReason: Uncategorized(opt_length)
          CheckInterrupts
          Return v24
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v21:ArrayExact = NewArray v16, v19
          v24:BasicObject = Send v21, :size # SendFallbackReason: Uncategorized(opt_size)
          CheckInterrupts
          Return v24
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :klass@1
          v6:CPtr = GetEP 0
          StoreField v6, :klass@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :klass@0x1000
          v16:FalseClass = Const Value(false)
          v18:BasicObject = GetConstant v14, :ARGV, v16
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
            test
        ");
        assert_contains_opcode("test", YARVINSN_getinstancevariable);
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string_function(&function), @"
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
        assert_snapshot!(hir_string_function(&function), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :block@1
          v6:CPtr = GetEP 0
          StoreField v6, :block@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:CUInt64 = LoadField v14, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v16:CBool = IsBlockParamModified v15
          CondBranch v16, bb4(), bb5()
        bb4():
          v18:BasicObject = LoadField v14, :block@0x1000
          Jump bb6(v18)
        bb5():
          v20:BasicObject = GetBlockParam :block, l0, EP@3
          Jump bb6(v20)
        bb6(v13:BasicObject):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_getblockparamproxy() {
        eval("
            def test(&block) = tap(&block)
        ");
        assert_contains_opcode("test", YARVINSN_getblockparamproxy);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :block@1
          v6:CPtr = GetEP 0
          StoreField v6, :block@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v15:CPtr = GetEP 0
          v16:CUInt64 = LoadField v15, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v17:CBool = IsBlockParamModified v16
          CondBranch v17, bb4(), bb5()
        bb4():
          v19:BasicObject = LoadField v15, :block@0x1000
          Jump bb6(v19)
        bb5():
          v21:CInt64 = LoadField v15, :VM_ENV_DATA_INDEX_SPECVAL@0x1002
          v22:CInt64 = GuardAnyBitSet v21, CUInt64(1)
          v23:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v23)
        bb6(v14:BasicObject):
          v26:BasicObject = Send v9, &block, :tap, v14 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_getblockparamproxy_modified() {
        eval("
            def test(&block)
              b = block
              tap(&block)
            end
        ");
        assert_contains_opcode("test", YARVINSN_getblockparamproxy);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :block@1
          v6:CPtr = GetEP 0
          StoreField v6, :block@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v16:CPtr = GetEP 0
          v17:CUInt64 = LoadField v16, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v18:CBool = IsBlockParamModified v17
          CondBranch v18, bb4(), bb5()
        bb4():
          v20:BasicObject = LoadField v16, :block@0x1000
          Jump bb6(v20)
        bb5():
          v22:BasicObject = GetBlockParam :block, l0, EP@4
          Jump bb6(v22)
        bb6(v15:BasicObject):
          SetLocal :b, l0, EP@3, v15
          v30:CPtr = GetEP 0
          v31:CUInt64 = LoadField v30, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v32:CBool = IsBlockParamModified v31
          CondBranch v32, bb7(), bb8()
        bb7():
          v34:BasicObject = LoadField v30, :block@0x1000
          Jump bb9(v34)
        bb8():
          v36:CInt64 = LoadField v30, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v37:CInt64 = GuardAnyBitSet v36, CUInt64(1)
          v38:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb9(v38)
        bb9(v29:BasicObject):
          v41:BasicObject = Send v11, &block, :tap, v29 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_getblockparamproxy_modified_nested_block() {
        eval("
            def test(&block)
              proc do
                b = block
                tap(&block)
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
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :b@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v14:CPtr = GetEP 1
          v15:CUInt64 = LoadField v14, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v16:CBool = IsBlockParamModified v15
          CondBranch v16, bb4(), bb5()
        bb4():
          v18:BasicObject = LoadField v14, :block@0x1000
          Jump bb6(v18)
        bb5():
          v20:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb6(v20)
        bb6(v13:BasicObject):
          SetLocal :b, l0, EP@3, v13
          v28:CPtr = GetEP 1
          v29:CUInt64 = LoadField v28, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v30:CBool = IsBlockParamModified v29
          CondBranch v30, bb7(), bb8()
        bb7():
          v32:BasicObject = LoadField v28, :block@0x1000
          Jump bb9(v32)
        bb8():
          v34:CInt64 = LoadField v28, :VM_ENV_DATA_INDEX_SPECVAL@0x1002
          v35:CInt64 = GuardAnyBitSet v34, CUInt64(1)
          v36:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb9(v36)
        bb9(v27:BasicObject):
          v39:BasicObject = Send v9, &block, :tap, v27 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v39
        ");
    }

    #[test]
    fn test_getblockparamproxy_polymorphic_none_and_iseq() {
        set_call_threshold(3);
        eval("
            def test(&block)
              0.then(&block)
            end

            test
            test { 1 }
        ");
        assert_contains_opcode("test", YARVINSN_getblockparamproxy);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :block@1
          v6:CPtr = GetEP 0
          StoreField v6, :block@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:Fixnum[0] = Const Value(0)
          v16:CPtr = GetEP 0
          v17:CUInt64 = LoadField v16, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v18:CBool = IsBlockParamModified v17
          CondBranch v18, bb4(), bb5()
        bb4():
          v20:BasicObject = LoadField v16, :block@0x1000
          Jump bb6(v20)
        bb5():
          v22:CInt64 = LoadField v16, :VM_ENV_DATA_INDEX_SPECVAL@0x1002
          v23:CInt64[1] = Const CInt64(1)
          v24:CInt64 = IntAnd v22, v23
          v25:CBool = IsBitEqual v24, v23
          CondBranch v25, bb7(), bb9()
        bb7():
          v27:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v27)
        bb9():
          v29:CInt64[0] = Const CInt64(0)
          v30:CBool = IsBitEqual v22, v29
          CondBranch v30, bb8(), bb10()
        bb8():
          v32:NilClass = Const Value(nil)
          Jump bb6(v32)
        bb6(v15:BasicObject):
          v36:BasicObject = Send v13, &block, :then, v15 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v36
        bb10():
          SideExit BlockParamProxyProfileNotCovered
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
          v11:CPtr = GetEP 1
          v12:CUInt64 = LoadField v11, :VM_ENV_DATA_INDEX_FLAGS@0x1000
          v13:CBool = IsBlockParamModified v12
          CondBranch v13, bb4(), bb5()
        bb4():
          v15:BasicObject = LoadField v11, :block@0x1001
          Jump bb6(v15)
        bb5():
          v17:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb6(v17)
        bb6(v10:BasicObject):
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_setblockparam() {
        eval("
            def test(&block)
              block = nil
            end
        ");
        assert_contains_opcode("test", YARVINSN_setblockparam);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :block@1
          v6:CPtr = GetEP 0
          StoreField v6, :block@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:NilClass = Const Value(nil)
          SetLocal :block, l0, EP@3, v13
          v17:CPtr = GetEP 0
          v18:CInt64 = LoadField v17, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v19:CInt64[512] = Const CInt64(512)
          v20:CInt64 = IntOr v18, v19
          StoreField v17, :VM_ENV_DATA_INDEX_FLAGS@0x1001, v20
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_setblockparam_nested_block() {
        eval("
            def test(&block)
              proc do
                block = nil
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
          v10:NilClass = Const Value(nil)
          SetLocal :block, l1, EP@3, v10
          v14:CPtr = GetEP 1
          v15:CInt64 = LoadField v14, :VM_ENV_DATA_INDEX_FLAGS@0x1000
          v16:CInt64[512] = Const CInt64(512)
          v17:CInt64 = IntOr v15, v16
          StoreField v14, :VM_ENV_DATA_INDEX_FLAGS@0x1000, v17
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_splatkw_unprofiled_side_exits() {
        eval("
            def foo(**kw, &b) = kw
            def test(**kw, &b) = foo(**kw, &b)
        ");
        assert_contains_opcode("test", YARVINSN_splatkw);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :kw@1
          v6:CPtr = GetEP 0
          StoreField v6, :kw@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :kw@0x1000
          v20:CPtr = GetEP 0
          v21:CUInt64 = LoadField v20, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v22:CBool = IsBlockParamModified v21
          CondBranch v22, bb4(), bb5()
        bb4():
          v24:BasicObject = LoadField v20, :b@0x1001
          Jump bb6(v24)
        bb5():
          v26:CInt64 = LoadField v20, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v27:CInt64 = GuardAnyBitSet v26, CUInt64(1)
          v28:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v28)
        bb6(v19:BasicObject):
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :*@2
          StoreField v6, :*@0x1001, v8
          v10:BasicObject = LoadArg :**@3
          StoreField v6, :**@0x1002, v10
          v12:BasicObject = LoadArg :&@4
          StoreField v6, :&@0x1003, v12
          v14:NilClass = Const Value(nil)
          StoreField v6, :...@0x1004, v14
          Jump bb3(v4)
        bb3(v17:BasicObject):
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :a@0x1000
          v25:CPtr = GetEP 0
          v26:BasicObject = LoadField v25, :*@0x1001
          v28:ArrayExact = ToArray v26
          v30:CPtr = GetEP 0
          v31:BasicObject = LoadField v30, :**@0x1002
          v34:CPtr = GetEP 0
          v35:CUInt64 = LoadField v34, :VM_ENV_DATA_INDEX_FLAGS@0x1005
          v36:CBool = IsBlockParamModified v35
          CondBranch v36, bb4(), bb5()
        bb4():
          v38:BasicObject = LoadField v34, :&@0x1003
          Jump bb6(v38)
        bb5():
          v40:CInt64 = LoadField v34, :VM_ENV_DATA_INDEX_SPECVAL@0x1006
          v41:CInt64[0] = GuardBitEquals v40, CInt64(0)
          v42:NilClass = Const Value(nil)
          Jump bb6(v42)
        bb6(v33:BasicObject):
          v45:NilClass = GuardType v31, NilClass
          v47:BasicObject = Send v17, &block, :foo, v23, v28, v45, v33 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v47
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :kw@1
          v6:CPtr = GetEP 0
          StoreField v6, :kw@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :kw@0x1000
          v20:CPtr = GetEP 0
          v21:CUInt64 = LoadField v20, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v22:CBool = IsBlockParamModified v21
          CondBranch v22, bb4(), bb5()
        bb4():
          v24:BasicObject = LoadField v20, :b@0x1001
          Jump bb6(v24)
        bb5():
          v26:CInt64 = LoadField v20, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v27:CInt64 = GuardAnyBitSet v26, CUInt64(1)
          v28:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v28)
        bb6(v19:BasicObject):
          v31:HashExact = GuardType v17, HashExact
          v33:BasicObject = Send v11, &block, :foo, v31, v19 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v33
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :kw@1
          v6:CPtr = GetEP 0
          StoreField v6, :kw@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :kw@0x1000
          v20:CPtr = GetEP 0
          v21:CUInt64 = LoadField v20, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v22:CBool = IsBlockParamModified v21
          CondBranch v22, bb4(), bb5()
        bb4():
          v24:BasicObject = LoadField v20, :b@0x1001
          Jump bb6(v24)
        bb5():
          v26:CInt64 = LoadField v20, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v27:CInt64 = GuardAnyBitSet v26, CUInt64(1)
          v28:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v28)
        bb6(v19:BasicObject):
          v31:HashExact = GuardType v17, HashExact
          v33:BasicObject = Send v11, &block, :foo, v31, v19 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v33
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :*@2
          StoreField v6, :*@0x1001, v8
          v10:BasicObject = LoadArg :**@3
          StoreField v6, :**@0x1002, v10
          v12:BasicObject = LoadArg :&@4
          StoreField v6, :&@0x1003, v12
          v14:NilClass = Const Value(nil)
          StoreField v6, :...@0x1004, v14
          Jump bb3(v4)
        bb3(v17:BasicObject):
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :a@0x1000
          v25:CPtr = GetEP 0
          v26:BasicObject = LoadField v25, :*@0x1001
          v28:ArrayExact = ToArray v26
          v30:CPtr = GetEP 0
          v31:BasicObject = LoadField v30, :**@0x1002
          v34:CPtr = GetEP 0
          v35:CUInt64 = LoadField v34, :VM_ENV_DATA_INDEX_FLAGS@0x1005
          v36:CBool = IsBlockParamModified v35
          CondBranch v36, bb4(), bb5()
        bb4():
          v38:BasicObject = LoadField v34, :&@0x1003
          Jump bb6(v38)
        bb5():
          v40:CInt64 = LoadField v34, :VM_ENV_DATA_INDEX_SPECVAL@0x1006
          v41:CInt64[0] = GuardBitEquals v40, CInt64(0)
          v42:NilClass = Const Value(nil)
          Jump bb6(v42)
        bb6(v33:BasicObject):
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
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :obj@1
          v6:CPtr = GetEP 0
          StoreField v6, :obj@0x1000, v5
          v8:BasicObject = LoadArg :block@2
          StoreField v6, :block@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :obj@0x1000
          v20:CPtr = GetEP 0
          v21:CUInt64 = LoadField v20, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v22:CBool = IsBlockParamModified v21
          CondBranch v22, bb4(), bb5()
        bb4():
          v24:BasicObject = LoadField v20, :block@0x1001
          Jump bb6(v24)
        bb5():
          v26:CInt64 = LoadField v20, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v27:CInt64 = GuardAnyBitSet v26, CUInt64(1)
          v28:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v28)
        bb6(v19:BasicObject):
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:ArrayExact = ToNewArray v14
          CheckInterrupts
          Return v16
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v15:ArrayExact = NewArray v13
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :a@0x1000
          v20:ArrayExact = ToArray v18
          ArrayExtend v15, v20
          CheckInterrupts
          Return v15
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:ArrayExact = ToNewArray v14
          v18:Fixnum[1] = Const Value(1)
          v20:CUInt64 = LoadField v16, :RBASIC_FLAGS@0x1001
          v21:CUInt64 = GuardNoBitsSet v20, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v16, v18
          CheckInterrupts
          Return v16
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :a@0x1000
          v16:ArrayExact = ToNewArray v14
          v18:Fixnum[1] = Const Value(1)
          v20:Fixnum[2] = Const Value(2)
          v22:Fixnum[3] = Const Value(3)
          v24:CUInt64 = LoadField v16, :RBASIC_FLAGS@0x1001
          v25:CUInt64 = GuardNoBitsSet v24, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v16, v18
          ArrayPush v16, v20
          ArrayPush v16, v22
          CheckInterrupts
          Return v16
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:NilClass = Const Value(nil)
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :a@0x1000
          v20:CPtr = GetEP 0
          v21:BasicObject = LoadField v20, :b@0x1001
          v23:Fixnum[1] = Const Value(1)
          v27:BasicObject = Send v18, :[]=, v21, v23 # SendFallbackReason: Uncategorized(opt_aset)
          CheckInterrupts
          Return v23
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :a@1
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:BasicObject = LoadArg :b@2
          StoreField v6, :b@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :a@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :b@0x1001
          v22:BasicObject = Send v16, :[], v19 # SendFallbackReason: Uncategorized(opt_aref)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          v17:BasicObject = Send v14, :empty? # SendFallbackReason: Uncategorized(opt_empty_p)
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          v17:BasicObject = Send v14, :succ # SendFallbackReason: Uncategorized(opt_succ)
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          v8:BasicObject = LoadArg :y@2
          StoreField v6, :y@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :x@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :y@0x1001
          v22:BasicObject = Send v16, :&, v19 # SendFallbackReason: Uncategorized(opt_and)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          v8:BasicObject = LoadArg :y@2
          StoreField v6, :y@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :x@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :y@0x1001
          v22:BasicObject = Send v16, :|, v19 # SendFallbackReason: Uncategorized(opt_or)
          CheckInterrupts
          Return v22
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          v17:BasicObject = Send v14, :! # SendFallbackReason: Uncategorized(opt_not)
          CheckInterrupts
          Return v17
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :regexp@1
          v6:CPtr = GetEP 0
          StoreField v6, :regexp@0x1000, v5
          v8:BasicObject = LoadArg :matchee@2
          StoreField v6, :matchee@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :regexp@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :matchee@0x1001
          v22:BasicObject = Send v16, :=~, v19 # SendFallbackReason: Uncategorized(opt_regexpmatch2)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @"
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
          v10:ClassSubclass[VMFrozenCore] = Const Value(VALUE(0x1000))
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
        assert_snapshot!(hir_strings!("reverse_odd", "reverse_even"), @"
        fn reverse_odd@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :c@0x1002, v10
          Jump bb3(v4)
        bb3(v13:BasicObject):
          PatchPoint SingleRactorMode
          v18:BasicObject = GetIvar v13, :@a
          PatchPoint SingleRactorMode
          v21:BasicObject = GetIvar v13, :@b
          PatchPoint SingleRactorMode
          v24:BasicObject = GetIvar v13, :@c
          SetLocal :a, l0, EP@5, v18
          SetLocal :b, l0, EP@4, v21
          SetLocal :c, l0, EP@3, v24
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :a@0x1000
          v37:CPtr = GetEP 0
          v38:BasicObject = LoadField v37, :b@0x1001
          v40:CPtr = GetEP 0
          v41:BasicObject = LoadField v40, :c@0x1002
          v43:ArrayExact = NewArray v35, v38, v41
          CheckInterrupts
          Return v43

        fn reverse_even@<compiled>:8:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :a@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :b@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :c@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :d@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          PatchPoint SingleRactorMode
          v20:BasicObject = GetIvar v15, :@a
          PatchPoint SingleRactorMode
          v23:BasicObject = GetIvar v15, :@b
          PatchPoint SingleRactorMode
          v26:BasicObject = GetIvar v15, :@c
          PatchPoint SingleRactorMode
          v29:BasicObject = GetIvar v15, :@d
          SetLocal :a, l0, EP@6, v20
          SetLocal :b, l0, EP@5, v23
          SetLocal :c, l0, EP@4, v26
          SetLocal :d, l0, EP@3, v29
          v41:CPtr = GetEP 0
          v42:BasicObject = LoadField v41, :a@0x1000
          v44:CPtr = GetEP 0
          v45:BasicObject = LoadField v44, :b@0x1001
          v47:CPtr = GetEP 0
          v48:BasicObject = LoadField v47, :c@0x1002
          v50:CPtr = GetEP 0
          v51:BasicObject = LoadField v50, :d@0x1003
          v53:ArrayExact = NewArray v42, v45, v48, v51
          CheckInterrupts
          Return v53
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          CheckInterrupts
          v18:CBool = IsNil v14
          v19:NilClass = Const Value(nil)
          CondBranch v18, bb4(v9, v19), bb5()
        bb5():
          v21:NotNil = RefineType v14, NotNil
          v23:BasicObject = Send v21, :itself # SendFallbackReason: Uncategorized(opt_send_without_block)
          Jump bb4(v9, v23)
        bb4(v25:BasicObject, v26:BasicObject):
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          CheckInterrupts
          v17:CBool = Test v14
          v18:Falsy = RefineType v14, Falsy
          CondBranch v17, bb6(), bb4(v9)
        bb6():
          v20:Truthy = RefineType v14, Truthy
          v23:CPtr = GetEP 0
          v24:BasicObject = LoadField v23, :x@0x1000
          CheckInterrupts
          v28:CBool = IsNil v24
          v29:NilClass = Const Value(nil)
          CondBranch v28, bb5(v9, v29), bb7()
        bb7():
          v31:NotNil = RefineType v24, NotNil
          v33:BasicObject = Send v31, :itself # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v33
        bb4(v38:BasicObject):
          v42:Fixnum[4] = Const Value(4)
          Jump bb5(v38, v42)
        bb5(v44:BasicObject, v45:NilClass|Fixnum):
          CheckInterrupts
          Return v45
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :x@0x1000
          CheckInterrupts
          v17:CBool = Test v14
          v18:Falsy = RefineType v14, Falsy
          CondBranch v17, bb7(), bb6(v9)
        bb7():
          v20:Truthy = RefineType v14, Truthy
          v23:CPtr = GetEP 0
          v24:BasicObject = LoadField v23, :x@0x1000
          CheckInterrupts
          v27:CBool = Test v24
          v28:Falsy = RefineType v24, Falsy
          CondBranch v27, bb8(), bb5(v9)
        bb8():
          v30:Truthy = RefineType v24, Truthy
          v33:CPtr = GetEP 0
          v34:BasicObject = LoadField v33, :x@0x1000
          CheckInterrupts
          v37:CBool = Test v34
          v38:Falsy = RefineType v34, Falsy
          CondBranch v37, bb9(), bb4(v9)
        bb9():
          v40:Truthy = RefineType v34, Truthy
          v43:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v43
        bb4(v66:BasicObject):
          v70:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v70
        bb5(v57:BasicObject):
          v61:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v61
        bb6(v48:BasicObject):
          v52:Fixnum[6] = Const Value(6)
          CheckInterrupts
          Return v52
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :arg@1
          v6:CPtr = GetEP 0
          StoreField v6, :arg@0x1000, v5
          v8:BasicObject = LoadArg :exception@2
          StoreField v6, :exception@0x1001, v8
          v10:BasicObject = LoadField v6, :<empty>@0x1002
          Jump bb3(v4)
        bb3(v12:BasicObject):
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :arg@0x1000
          v18:BasicObject = LoadField v16, :exception@0x1001
          v19:Float = InvokeBuiltin rb_f_float, v12, v17, v18
          Jump bb4(v12, v19)
        bb4(v21:BasicObject, v22:Float):
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_invokebuiltin_cexpr_annotated() {
        assert_contains_opcode("class", YARVINSN_opt_invokebuiltin_delegate_leave);
        assert_snapshot!(hir_string("class"), @"
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
          v10:CPtr = GetEP 0
          v11:Class = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v11)
        bb4(v13:BasicObject, v14:Class):
          CheckInterrupts
          Return v14
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :name@1
          v6:CPtr = GetEP 0
          StoreField v6, :name@0x1000, v5
          v8:BasicObject = LoadArg :encoding@2
          StoreField v6, :encoding@0x1001, v8
          v10:BasicObject = LoadField v6, :<empty>@0x1002
          v11:BasicObject = LoadArg :block@3
          StoreField v6, :block@0x1003, v11
          v13:NilClass = Const Value(nil)
          StoreField v6, :dir@0x1004, v13
          Jump bb3(v4)
        bb3(v16:BasicObject):
          v20:CPtr = GetEP 0
          v21:BasicObject = LoadField v20, :name@0x1000
          v22:BasicObject = LoadField v20, :encoding@0x1001
          v23:BasicObject = InvokeBuiltin dir_s_open, v16, v21, v22
          SetLocal :dir, l0, EP@3, v23
          v29:CPtr = GetEP 0
          v30:CUInt64 = LoadField v29, :VM_ENV_DATA_INDEX_FLAGS@0x1005
          v31:CBool = IsBlockParamModified v30
          CondBranch v31, bb5(), bb6()
        bb5():
          v33:BasicObject = LoadField v29, :block@0x1003
          Jump bb7(v33)
        bb6():
          v35:CInt64 = LoadField v29, :VM_ENV_DATA_INDEX_SPECVAL@0x1006
          v36:CInt64 = GuardAnyBitSet v35, CUInt64(1)
          v37:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb7(v37)
        bb7(v28:BasicObject):
          CheckInterrupts
          v41:CBool = Test v28
          v42:Falsy = RefineType v28, Falsy
          CondBranch v41, bb8(), bb4(v16)
        bb8():
          v44:Truthy = RefineType v28, Truthy
          v47:CPtr = GetEP 0
          v48:BasicObject = LoadField v47, :dir@0x1004
          v50:BasicObject = InvokeBlock, v48 # SendFallbackReason: InvokeBlock: not yet specialized
          v53:CPtr = GetEP 0
          v54:BasicObject = LoadField v53, :dir@0x1004
          v55:BasicObject = InvokeBuiltin dir_s_close, v16, v54
          CheckInterrupts
          Return v50
        bb4(v61:BasicObject):
          v65:CPtr = GetEP 0
          v66:BasicObject = LoadField v65, :dir@0x1004
          CheckInterrupts
          Return v66
        ");
    }

    #[test]
    fn test_invokebuiltin_delegate_without_args() {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("GC", "enable"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_opt_invokebuiltin_delegate_leave), "iseq GC.enable does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @"
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
          v10:CPtr = GetEP 0
          v11:BasicObject = InvokeBuiltin gc_enable, v6
          Jump bb4(v6, v11)
        bb4(v13:BasicObject, v14:BasicObject):
          CheckInterrupts
          Return v14
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :full_mark@1
          v6:CPtr = GetEP 0
          StoreField v6, :full_mark@0x1000, v5
          v8:BasicObject = LoadArg :immediate_mark@2
          StoreField v6, :immediate_mark@0x1001, v8
          v10:BasicObject = LoadArg :immediate_sweep@3
          StoreField v6, :immediate_sweep@0x1002, v10
          v12:BasicObject = LoadField v6, :<empty>@0x1003
          Jump bb3(v4)
        bb3(v14:BasicObject):
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :full_mark@0x1000
          v21:CPtr = GetEP 0
          v22:BasicObject = LoadField v21, :immediate_mark@0x1001
          v24:CPtr = GetEP 0
          v25:BasicObject = LoadField v24, :immediate_sweep@0x1002
          v27:FalseClass = Const Value(false)
          v29:BasicObject = InvokeBuiltin gc_start_internal, v14, v19, v22, v25, v27
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_invoke_leaf_builtin_symbol_name() {
        let iseq = crate::cruby::with_rubyvm(|| get_instance_method_iseq("Symbol", "name"));
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @"
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
          v10:CPtr = GetEP 0
          v11:StringExact = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v11)
        bb4(v13:BasicObject, v14:StringExact):
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_invoke_leaf_builtin_symbol_to_s() {
        let iseq = crate::cruby::with_rubyvm(|| get_instance_method_iseq("Symbol", "to_s"));
        let function = iseq_to_hir(iseq).unwrap();
        assert_snapshot!(hir_string_function(&function), @"
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
          v10:CPtr = GetEP 0
          v11:StringExact = InvokeBuiltin leaf <inline_expr>, v6
          Jump bb4(v6, v11)
        bb4(v13:BasicObject, v14:StringExact):
          CheckInterrupts
          Return v14
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:NilClass = Const Value(nil)
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :x@0x1000
          v18:Fixnum[0] = Const Value(0)
          v20:Fixnum[1] = Const Value(1)
          v23:BasicObject = Send v16, :[], v18, v20 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          v27:CBool = Test v23
          v28:Truthy = RefineType v23, Truthy
          CondBranch v27, bb4(v9, v13, v16, v18, v20, v28), bb5()
        bb4(v42:BasicObject, v43:NilClass, v44:BasicObject, v45:Fixnum[0], v46:Fixnum[1], v47:Truthy):
          CheckInterrupts
          Return v47
        bb5():
          v30:Falsy = RefineType v23, Falsy
          v33:Fixnum[2] = Const Value(2)
          v36:BasicObject = Send v16, :[]=, v18, v20, v33 # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_objtostring_anytostring() {
        eval("
            def test = \"#{1}\"
        ");
        assert_contains_opcode("test", YARVINSN_objtostring);
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
        assert_snapshot!(hir_strings!("throw_return", "throw_break"), @"
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
        assert_snapshot!(hir_string("test"), @"
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
          v10:BasicObject = InvokeBlock # SendFallbackReason: InvokeBlock: not yet specialized
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :x@1
          v6:CPtr = GetEP 0
          StoreField v6, :x@0x1000, v5
          v8:BasicObject = LoadArg :y@2
          StoreField v6, :y@0x1001, v8
          Jump bb3(v4)
        bb3(v11:BasicObject):
          v15:CPtr = GetEP 0
          v16:BasicObject = LoadField v15, :x@0x1000
          v18:CPtr = GetEP 0
          v19:BasicObject = LoadField v18, :y@0x1001
          v21:BasicObject = InvokeBlock, v16, v19 # SendFallbackReason: InvokeBlock: not yet specialized
          CheckInterrupts
          Return v21
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :o@1
          v6:CPtr = GetEP 0
          StoreField v6, :o@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :a@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :b@0x1002, v10
          Jump bb3(v4)
        bb3(v13:BasicObject):
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :o@0x1000
          v21:ArrayExact = GuardType v18, ArrayExact
          v22:CInt64 = ArrayLength v21
          v23:CInt64[2] = Const CInt64(2)
          v24:CInt64 = GuardGreaterEq v22, v23
          v25:CInt64[1] = Const CInt64(1)
          v26:BasicObject = ArrayAref v21, v25
          v27:CInt64[0] = Const CInt64(0)
          v28:BasicObject = ArrayAref v21, v27
          SetLocal :a, l0, EP@4, v28
          SetLocal :b, l0, EP@3, v26
          CheckInterrupts
          Return v18
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :o@1
          v6:CPtr = GetEP 0
          StoreField v6, :o@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :a@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :b@0x1002, v10
          Jump bb3(v4)
        bb3(v13:BasicObject):
          v17:CPtr = GetEP 0
          v18:BasicObject = LoadField v17, :o@0x1000
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :o@1
          v6:CPtr = GetEP 0
          StoreField v6, :o@0x1000, v5
          v8:NilClass = Const Value(nil)
          StoreField v6, :a@0x1001, v8
          v10:NilClass = Const Value(nil)
          StoreField v6, :b@0x1002, v10
          v12:NilClass = Const Value(nil)
          StoreField v6, :c@0x1003, v12
          Jump bb3(v4)
        bb3(v15:BasicObject):
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :o@0x1000
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :kw@1
          v6:CPtr = GetEP 0
          StoreField v6, :kw@0x1000, v5
          v8:BasicObject = LoadField v6, :<empty>@0x1001
          Jump bb3(v4)
        bb3(v10:BasicObject):
          v13:CPtr = GetEP 0
          v14:BasicObject = LoadField v13, :<empty>@0x1001
          v15:BoolExact = FixnumBitCheck v14, 0
          CheckInterrupts
          v18:CBool = Test v15
          v19:TrueClass = RefineType v15, Truthy
          CondBranch v18, bb4(v10), bb5()
        bb5():
          v21:FalseClass = RefineType v15, Falsy
          v23:Fixnum[1] = Const Value(1)
          v25:Fixnum[1] = Const Value(1)
          v28:BasicObject = Send v23, :+, v25 # SendFallbackReason: Uncategorized(opt_plus)
          SetLocal :kw, l0, EP@4, v28
          Jump bb4(v10)
        bb4(v32:BasicObject):
          v36:CPtr = GetEP 0
          v37:BasicObject = LoadField v36, :kw@0x1000
          CheckInterrupts
          Return v37
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
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:BasicObject = LoadArg :k1@1
          v6:CPtr = GetEP 0
          StoreField v6, :k1@0x1000, v5
          v8:BasicObject = LoadArg :k2@2
          StoreField v6, :k2@0x1001, v8
          v10:BasicObject = LoadArg :k3@3
          StoreField v6, :k3@0x1002, v10
          v12:BasicObject = LoadArg :k4@4
          StoreField v6, :k4@0x1003, v12
          v14:BasicObject = LoadArg :k5@5
          StoreField v6, :k5@0x1004, v14
          v16:BasicObject = LoadArg :k6@6
          StoreField v6, :k6@0x1005, v16
          v18:BasicObject = LoadArg :k7@7
          StoreField v6, :k7@0x1006, v18
          v20:BasicObject = LoadArg :k8@8
          StoreField v6, :k8@0x1007, v20
          v22:BasicObject = LoadArg :k9@9
          StoreField v6, :k9@0x1008, v22
          v24:BasicObject = LoadArg :k10@10
          StoreField v6, :k10@0x1009, v24
          v26:BasicObject = LoadArg :k11@11
          StoreField v6, :k11@0x100a, v26
          v28:BasicObject = LoadArg :k12@12
          StoreField v6, :k12@0x100b, v28
          v30:BasicObject = LoadArg :k13@13
          StoreField v6, :k13@0x100c, v30
          v32:BasicObject = LoadArg :k14@14
          StoreField v6, :k14@0x100d, v32
          v34:BasicObject = LoadArg :k15@15
          StoreField v6, :k15@0x100e, v34
          v36:BasicObject = LoadArg :k16@16
          StoreField v6, :k16@0x100f, v36
          v38:BasicObject = LoadArg :k17@17
          StoreField v6, :k17@0x1010, v38
          v40:BasicObject = LoadArg :k18@18
          StoreField v6, :k18@0x1011, v40
          v42:BasicObject = LoadArg :k19@19
          StoreField v6, :k19@0x1012, v42
          v44:BasicObject = LoadArg :k20@20
          StoreField v6, :k20@0x1013, v44
          v46:BasicObject = LoadArg :k21@21
          StoreField v6, :k21@0x1014, v46
          v48:BasicObject = LoadArg :k22@22
          StoreField v6, :k22@0x1015, v48
          v50:BasicObject = LoadArg :k23@23
          StoreField v6, :k23@0x1016, v50
          v52:BasicObject = LoadArg :k24@24
          StoreField v6, :k24@0x1017, v52
          v54:BasicObject = LoadArg :k25@25
          StoreField v6, :k25@0x1018, v54
          v56:BasicObject = LoadArg :k26@26
          StoreField v6, :k26@0x1019, v56
          v58:BasicObject = LoadArg :k27@27
          StoreField v6, :k27@0x101a, v58
          v60:BasicObject = LoadArg :k28@28
          StoreField v6, :k28@0x101b, v60
          v62:BasicObject = LoadArg :k29@29
          StoreField v6, :k29@0x101c, v62
          v64:BasicObject = LoadArg :k30@30
          StoreField v6, :k30@0x101d, v64
          v66:BasicObject = LoadArg :k31@31
          StoreField v6, :k31@0x101e, v66
          v68:BasicObject = LoadArg :k32@32
          StoreField v6, :k32@0x101f, v68
          v70:BasicObject = LoadArg :k33@33
          StoreField v6, :k33@0x1020, v70
          v72:BasicObject = LoadField v6, :<empty>@0x1021
          Jump bb3(v4)
        bb3(v74:BasicObject):
          SideExit TooManyKeywordParameters
        ");
    }

    #[test]
    fn test_array_each() {
        assert_snapshot!(hir_string_proc("Array.instance_method(:each)"), @"
        fn each@<internal:array>:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          v5:NilClass = Const Value(nil)
          v6:CPtr = GetEP 0
          StoreField v6, :i@0x1000, v5
          Jump bb3(v4)
        bb3(v9:BasicObject):
          v13:NilClass = Const Value(nil)
          v15:TrueClass|NilClass = Defined yield, v13
          v17:CBool = Test v15
          v18:NilClass = RefineType v15, Falsy
          CondBranch v17, bb9(), bb4(v9)
        bb9():
          v20:TrueClass = RefineType v15, Truthy
          Jump bb6(v9)
        bb6(v30:BasicObject):
          v34:Fixnum[0] = Const Value(0)
          SetLocal :i, l0, EP@3, v34
          Jump bb8(v30)
        bb8(v47:BasicObject):
          v50:CPtr = GetEP 0
          v51:BasicObject = LoadField v50, :i@0x1000
          v52:BoolExact = InvokeBuiltin rb_jit_ary_at_end, v47, v51
          v54:CBool = Test v52
          v55:FalseClass = RefineType v52, Falsy
          CondBranch v54, bb10(), bb7(v47)
        bb10():
          v57:TrueClass = RefineType v52, Truthy
          v59:NilClass = Const Value(nil)
          CheckInterrupts
          Return v47
        bb7(v67:BasicObject):
          v71:CPtr = GetEP 0
          v72:BasicObject = LoadField v71, :i@0x1000
          v73:BasicObject = InvokeBuiltin rb_jit_ary_at, v67, v72
          v75:BasicObject = InvokeBlock, v73 # SendFallbackReason: InvokeBlock: not yet specialized
          v79:CPtr = GetEP 0
          v80:BasicObject = LoadField v79, :i@0x1000
          v81:Fixnum = InvokeBuiltin rb_jit_fixnum_inc, v67, v80
          SetLocal :i, l0, EP@3, v81
          Jump bb8(v67)
        bb4(v23:BasicObject):
          v27:CPtr = GetEP 0
          v28:BasicObject = InvokeBuiltin <inline_expr>, v23
          Jump bb5(v23, v28)
        bb5(v40:BasicObject, v41:BasicObject):
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_induce_side_exit() {
        eval("
          class NonTopLexicalScope
            RubyVM = 0
            def test
              RubyVM::ZJIT.induce_side_exit! # lexical scope dependant -- should not recognize
              ::RubyVM::ZJIT.induce_side_exit!
            end
          end
        ");
        assert_snapshot!(hir_string_proc("NonTopLexicalScope.instance_method(:test)"), @"
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
          v10:BasicObject = GetConstantPath 0x1000
          v12:BasicObject = Send v10, :induce_side_exit! # SendFallbackReason: Uncategorized(opt_send_without_block)
          v16:BasicObject = GetConstantPath 0x1000
          SideExit DirectiveInduced
        ");
    }

    #[test]
    fn test_induce_side_exit_sensitive_to_constant_state() {
        eval("
          def test = ::RubyVM::ZJIT.induce_side_exit!
        ");
        assert!(hir_string("test").contains("SideExit DirectiveInduced"));
        eval("
          class RubyVM
            remove_const(:ZJIT)
          end
        ");
        let hir_after_removal = hir_string("test");
        assert_eq!(false, hir_string("test").contains("SideExit DirectiveInduced"), "should not work when the constant lookup would fail");
        assert_snapshot!(hir_after_removal, @"
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
          v10:BasicObject = GetConstantPath 0x1000
          v12:BasicObject = Send v10, :induce_side_exit! # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_induce_side_exit_doesnt_work_when_method_after_undef() {
        eval("
          class << RubyVM::ZJIT
            undef :induce_side_exit!
          end
          def test = ::RubyVM::ZJIT.induce_side_exit!
        ");
        assert_eq!(false, hir_string("test").contains("SideExit DirectiveInduced"), "should not work after undef");
    }

    #[test]
    fn test_induce_compile_failure_does_not_trigger_autoload() {
        eval("
          class RubyVM
            remove_const(:ZJIT)
            autoload :ZJIT, 'a-file-that-does-not-exist-as-a-trap'
          end
          def test = ::RubyVM::ZJIT.induce_compile_failure!
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v10:BasicObject = GetConstantPath 0x1000
          v12:BasicObject = Send v10, :induce_compile_failure! # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_induce_compile_failure_checks_full_const_path() {
        eval("def test = ::RubyVM::ZJIT::TooDeep.induce_compile_failure!");
        assert_snapshot!(hir_string("test"), @"
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
          v10:BasicObject = GetConstantPath 0x1000
          v12:BasicObject = Send v10, :induce_compile_failure! # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_induce_compile_failure() {
        eval("def test = ::RubyVM::ZJIT.induce_compile_failure!");
        assert_compile_fails("test", ParseError::DirectiveInduced);
    }

    #[test]
    fn test_induce_breakpoint() {
        eval("def test = ::RubyVM::ZJIT.induce_breakpoint!");
        assert!(hir_string("test").contains("BreakPoint"));
    }

    #[test]
    fn test_induce_breakpoint_returns_nil() {
        eval("
          def test
            x = ::RubyVM::ZJIT.induce_breakpoint!
            x
          end
        ");
        let hir = hir_string("test");
        assert!(hir.contains("BreakPoint"));
        assert!(hir.contains("Return v"));
    }

    #[test]
    fn test_getspecialnumber() {
      eval("
        def test(a)
          a =~/(hello)/
          $1
        end
      ");
      assert_snapshot!(hir_string("test"), @"
      fn test@<compiled>:3:
      bb1():
        EntryPoint interpreter
        v1:BasicObject = LoadSelf
        Jump bb3(v1)
      bb2():
        EntryPoint JIT(0)
        v4:BasicObject = LoadArg :self@0
        v5:BasicObject = LoadArg :a@1
        v6:CPtr = GetEP 0
        StoreField v6, :a@0x1000, v5
        Jump bb3(v4)
      bb3(v9:BasicObject):
        v13:CPtr = GetEP 0
        v14:BasicObject = LoadField v13, :a@0x1000
        v16:RegexpExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
        v19:BasicObject = Send v14, :=~, v16 # SendFallbackReason: Uncategorized(opt_regexpmatch2)
        v23:StringExact|NilClass = GetSpecialNumber 2
        CheckInterrupts
        Return v23
      ");
    }

    #[test]
    fn test_getspecialsymbol() {
      eval("
        def test(a)
          a =~/(hello)/
          $&
        end
      ");
      assert_snapshot!(hir_string("test"), @"
      fn test@<compiled>:3:
      bb1():
        EntryPoint interpreter
        v1:BasicObject = LoadSelf
        Jump bb3(v1)
      bb2():
        EntryPoint JIT(0)
        v4:BasicObject = LoadArg :self@0
        v5:BasicObject = LoadArg :a@1
        v6:CPtr = GetEP 0
        StoreField v6, :a@0x1000, v5
        Jump bb3(v4)
      bb3(v9:BasicObject):
        v13:CPtr = GetEP 0
        v14:BasicObject = LoadField v13, :a@0x1000
        v16:RegexpExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
        v19:BasicObject = Send v14, :=~, v16 # SendFallbackReason: Uncategorized(opt_regexpmatch2)
        v23:StringExact|NilClass = GetSpecialSymbol LastMatch
        CheckInterrupts
        Return v23
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
        let _ = function.push_insn(bb0, Insn::CondBranch { val: v1, if_true: edge(bb2), if_false: edge(bb1) });
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
         let _ = function.push_insn(bb0, Insn::CondBranch { val: v1, if_true: edge(bb1), if_false: edge(bb1)});

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
         assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
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
        let _ = function.push_insn(bb0, Insn::CondBranch { val, if_true: edge(bb1), if_false: edge(bb2) });

        function.push_insn(bb2, Insn::Jump(edge(bb3)));
        function.push_insn(bb1, Insn::Jump(edge(bb3)));

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          CondBranch v0, bb2(), bb3()
        bb2():
          Jump bb4()
        bb3():
          Jump bb4()
        bb4():
          v4:Any = Const CBool(true)
          Return v4
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
        let _ = function.push_insn(bb1, Insn::CondBranch { val: v0, if_true: edge(bb2), if_false: edge(bb4) });

        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        let v1 = function.push_insn(bb3, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb3, Insn::CondBranch { val: v1, if_true: edge(bb5), if_false: edge(bb7) });

        function.push_insn(bb4, Insn::Jump(edge(bb5)));

        function.push_insn(bb5, Insn::Jump(edge(bb6)));

        function.push_insn(bb6, Insn::Jump(edge(bb7)));

        let retval = function.push_insn(bb7, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb7, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          Jump bb2()
        bb2():
          v1:Any = Const Value(false)
          CondBranch v1, bb3(), bb5()
        bb3():
          Jump bb4()
        bb4():
          v4:Any = Const Value(false)
          CondBranch v4, bb6(), bb8()
        bb5():
          Jump bb6()
        bb6():
          Jump bb7()
        bb7():
          Jump bb8()
        bb8():
          v9:Any = Const CBool(true)
          Return v9
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
        let _ = function.push_insn(bb0, Insn::CondBranch { val: v0, if_true: edge(bb1), if_false: edge(bb4) });

        let v1 = function.push_insn(bb1, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb1, Insn::CondBranch { val: v1, if_true: edge(bb2), if_false: edge(bb3) });

        function.push_insn(bb2, Insn::Jump(edge(bb3)));

        function.push_insn(bb4, Insn::Jump(edge(bb5)));

        let v2 = function.push_insn(bb5, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb5, Insn::CondBranch { val: v2, if_true: edge(bb3), if_false: edge(bb4) });

        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb3, Insn::Return { val: retval });

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          CondBranch v0, bb2(), bb5()
        bb2():
          v2:Any = Const Value(false)
          CondBranch v2, bb3(), bb4()
        bb3():
          Jump bb4()
        bb5():
          Jump bb6()
        bb6():
          v6:Any = Const Value(false)
          CondBranch v6, bb4(), bb5()
        bb4():
          v8:Any = Const CBool(true)
          Return v8
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
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
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
        //    ┌─────┐
        //    │ bb0 │
        //    └──┬──┘
        //       │
        //    ┌──▼──┐      ┌─────┐
        //  ┌►│ bb2 ├─────►│ bb1 │
        //  │ └──┬──┘  T   └──┬──┘
        //  │   F│            │
        //  │ ┌──▼──┐         │
        //  │ │ bb3 │         │
        //  │ └─────┘         │
        //  └─────────────────┘
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        let val = function.push_insn(bb2, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb2, Insn::CondBranch { val, if_true: edge(bb1), if_false: edge(bb3) });
        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb3, Insn::Return { val: retval });

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          Jump bb3()
        bb3():
          v1:Any = Const Value(false)
          CondBranch v1, bb2(), bb4()
        bb2():
          Jump bb3()
        bb4():
          v3:Any = Const CBool(true)
          Return v3
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
        let _ = function.push_insn(bb2, Insn::CondBranch { val: cond, if_true: edge(bb1), if_false: edge(bb3) });

        let cond = function.push_insn(bb3, Insn::Const { val: Const::Value(Qtrue) });
        let _ = function.push_insn(bb3, Insn::CondBranch { val: cond, if_true: edge(bb0), if_false: edge(bb4) });

        let retval = function.push_insn(bb4, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb4, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          Jump bb2()
        bb2():
          Jump bb3()
        bb3():
          v2:Any = Const Value(false)
          CondBranch v2, bb2(), bb4()
        bb4():
          v4:Any = Const Value(true)
          CondBranch v4, bb1(), bb5()
        bb5():
          v6:Any = Const CBool(true)
          Return v6
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
        let _ = function.push_insn(bb0, Insn::CondBranch { val: cond, if_true: edge(bb1), if_false: edge(bb3) });

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        let _ = function.push_insn(bb2, Insn::CondBranch { val: cond, if_true: edge(bb1), if_false: edge(bb5) });

        function.push_insn(bb3, Insn::Jump(edge(bb4)));

        let _ = function.push_insn(bb4, Insn::CondBranch { val: cond, if_true: edge(bb3), if_false: edge(bb5) });

        let _ = function.push_insn(bb5, Insn::CondBranch { val: cond, if_true: edge(bb0), if_false: edge(bb6) });

        let retval = function.push_insn(bb6, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb6, Insn::Return { val: retval });

        function.seal_entries();
        let cfi = ControlFlowInfo::new(&function);
        let dominators = Dominators::new(&function);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          CondBranch v0, bb2(), bb4()
        bb2():
          Jump bb3()
        bb3():
          CondBranch v0, bb2(), bb6()
        bb4():
          Jump bb5()
        bb5():
          CondBranch v0, bb4(), bb6()
        bb6():
          CondBranch v0, bb1(), bb7()
        bb7():
          v7:Any = Const CBool(true)
          Return v7
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

        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
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
        let bb6 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb0, Insn::Jump(edge(bb1)));
        let _ = function.push_insn(bb1, Insn::Jump(edge(bb2)));
        let _ = function.push_insn(bb2, Insn::Jump(edge(bb3)));
        let _ = function.push_insn(bb3, Insn::CondBranch {val: cond, if_true: edge(bb2), if_false: edge(bb4) });
        let _ = function.push_insn(bb4, Insn::CondBranch {val: cond, if_true: edge(bb1), if_false: edge(bb5) });
        let _ = function.push_insn(bb5, Insn::CondBranch {val: cond, if_true: edge(bb0), if_false: edge(bb6) });
        function.push_insn(bb6, Insn::Unreachable);

        function.seal_entries();
        assert_snapshot!(format!("{}", FunctionPrinter::without_snapshot(&function)), @"
        fn <manual>:
        bb1():
          v0:Any = Const Value(false)
          Jump bb2()
        bb2():
          Jump bb3()
        bb3():
          Jump bb4()
        bb4():
          CondBranch v0, bb3(), bb5()
        bb5():
          CondBranch v0, bb2(), bb6()
        bb6():
          CondBranch v0, bb1(), bb7()
        bb7():
          Unreachable
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
        function.seal_entries();

        let json = function.to_iongraph_pass("simple");
        assert_snapshot!(json.to_string(), @r#"{"name":"simple", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4098, "id":2, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[], "instructions":[{"ptr":4096, "id":0, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4097, "id":1, "opcode":"Return v0", "attributes":[], "inputs":[0], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_two_blocks() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb1)));

        let retval = function.push_insn(bb1, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb1, Insn::Return { val: retval });

        function.seal_entries();
        let json = function.to_iongraph_pass("two_blocks");
        assert_snapshot!(json.to_string(), @r#"{"name":"two_blocks", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4099, "id":3, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[2], "instructions":[{"ptr":4096, "id":0, "opcode":"Jump bb2()", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4098, "id":2, "loopDepth":0, "attributes":[], "predecessors":[1], "successors":[], "instructions":[{"ptr":4097, "id":1, "opcode":"Const CBool(false)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4098, "id":2, "opcode":"Return v1", "attributes":[], "inputs":[1], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_multiple_instructions() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;

        let val1 = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::Return { val: val1 });

        function.seal_entries();
        let json = function.to_iongraph_pass("multiple_instructions");
        assert_snapshot!(json.to_string(), @r#"{"name":"multiple_instructions", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4098, "id":2, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[], "instructions":[{"ptr":4096, "id":0, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4097, "id":1, "opcode":"Return v0", "attributes":[], "inputs":[0], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_conditional_branch() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::CondBranch { val: cond, if_true: edge(bb1), if_false: edge(bb2) });

        let retval1 = function.push_insn(bb2, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb2, Insn::Return { val: retval1 });

        let retval2 = function.push_insn(bb1, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb1, Insn::Return { val: retval2 });

        function.seal_entries();
        let json = function.to_iongraph_pass("conditional_branch");
        assert_snapshot!(json.to_string(), @r#"{"name":"conditional_branch", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4102, "id":6, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[2, 3], "instructions":[{"ptr":4096, "id":0, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4097, "id":1, "opcode":"CondBranch v0, bb2(), bb3()", "attributes":[], "inputs":[0], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4098, "id":2, "loopDepth":0, "attributes":[], "predecessors":[1], "successors":[], "instructions":[{"ptr":4100, "id":4, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4101, "id":5, "opcode":"Return v4", "attributes":[], "inputs":[4], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4099, "id":3, "loopDepth":0, "attributes":[], "predecessors":[1], "successors":[], "instructions":[{"ptr":4098, "id":2, "opcode":"Const CBool(false)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4099, "id":3, "opcode":"Return v2", "attributes":[], "inputs":[2], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_loop_structure() {
        let mut function = Function::new(std::ptr::null());

        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);
        let bb3 = function.new_block(0);

        function.push_insn(bb0, Insn::Jump(edge(bb2)));

        let val = function.push_insn(bb2, Insn::Const { val: Const::Value(Qfalse) });
        let _ = function.push_insn(bb2, Insn::CondBranch { val, if_true: edge(bb1), if_false: edge(bb3) });
        let retval = function.push_insn(bb3, Insn::Const { val: Const::CBool(true) });
        let _ = function.push_insn(bb3, Insn::Return { val: retval });

        function.push_insn(bb1, Insn::Jump(edge(bb2)));

        function.seal_entries();
        let json = function.to_iongraph_pass("loop_structure");
        assert_snapshot!(json.to_string(), @r#"{"name":"loop_structure", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4102, "id":6, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[3], "instructions":[{"ptr":4096, "id":0, "opcode":"Jump bb3()", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4099, "id":3, "loopDepth":1, "attributes":["loopheader"], "predecessors":[1, 2], "successors":[2, 4], "instructions":[{"ptr":4097, "id":1, "opcode":"Const Value(false)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4098, "id":2, "opcode":"CondBranch v1, bb2(), bb4()", "attributes":[], "inputs":[1], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4098, "id":2, "loopDepth":1, "attributes":["backedge"], "predecessors":[3], "successors":[3], "instructions":[{"ptr":4101, "id":5, "opcode":"Jump bb3()", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4100, "id":4, "loopDepth":0, "attributes":[], "predecessors":[3], "successors":[], "instructions":[{"ptr":4099, "id":3, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4100, "id":4, "opcode":"Return v3", "attributes":[], "inputs":[3], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }

    #[test]
    fn test_multiple_successors() {
        let mut function = Function::new(std::ptr::null());
        let bb0 = function.entry_block;
        let bb1 = function.new_block(0);
        let bb2 = function.new_block(0);

        let cond = function.push_insn(bb0, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb0, Insn::CondBranch { val: cond, if_true: edge(bb1), if_false: edge(bb2) });

        let retval1 = function.push_insn(bb1, Insn::Const { val: Const::CBool(true) });
        function.push_insn(bb1, Insn::Return { val: retval1 });

        let retval2 = function.push_insn(bb2, Insn::Const { val: Const::CBool(false) });
        function.push_insn(bb2, Insn::Return { val: retval2 });

        function.seal_entries();
        let json = function.to_iongraph_pass("multiple_successors");
        assert_snapshot!(json.to_string(), @r#"{"name":"multiple_successors", "mir":{"blocks":[{"ptr":4096, "id":0, "loopDepth":0, "attributes":[], "predecessors":[], "successors":[1], "instructions":[{"ptr":4102, "id":6, "opcode":"Entries bb1", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4097, "id":1, "loopDepth":0, "attributes":[], "predecessors":[0], "successors":[2, 3], "instructions":[{"ptr":4096, "id":0, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4097, "id":1, "opcode":"CondBranch v0, bb2(), bb3()", "attributes":[], "inputs":[0], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4098, "id":2, "loopDepth":0, "attributes":[], "predecessors":[1], "successors":[], "instructions":[{"ptr":4098, "id":2, "opcode":"Const CBool(true)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4099, "id":3, "opcode":"Return v2", "attributes":[], "inputs":[2], "uses":[], "memInputs":[], "type":""}]}, {"ptr":4099, "id":3, "loopDepth":0, "attributes":[], "predecessors":[1], "successors":[], "instructions":[{"ptr":4100, "id":4, "opcode":"Const CBool(false)", "attributes":[], "inputs":[], "uses":[], "memInputs":[], "type":"Any"}, {"ptr":4101, "id":5, "opcode":"Return v4", "attributes":[], "inputs":[4], "uses":[], "memInputs":[], "type":""}]}]}, "lir":{"blocks":[]}}"#);
    }
 }
