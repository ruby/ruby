#[cfg(test)]
mod hir_opt_tests {
    use crate::hir::*;

    use crate::hir::tests::hir_build_tests::assert_contains_opcode;
    use crate::{hir_strings, options::*};
    use insta::assert_snapshot;

    #[track_caller]
    fn hir_string_function(function: &Function) -> String {
        format!("{}", FunctionPrinter::without_snapshot(function))
    }

    #[track_caller]
    fn hir_string_proc(proc: &str) -> String {
        let iseq = crate::cruby::with_rubyvm(|| get_proc_iseq(proc));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let mut function = iseq_to_hir(iseq).unwrap();
        function.optimize();
        function.validate().unwrap();
        hir_string_function(&function)
    }

    #[track_caller]
    fn hir_string(method: &str) -> String {
        hir_string_proc(&format!("{}.method(:{})", "self", method))
    }

    #[test]
    fn test_fold_iftrue_away() {
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
          v25:Fixnum[3] = Const Value(3)
          Return v25
        ");
    }

    #[test]
    fn test_fold_iftrue_into_jump() {
        eval("
            def test
              cond = false
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
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:BasicObject, v9:NilClass):
          v13:FalseClass = Const Value(false)
          CheckInterrupts
          v35:Fixnum[4] = Const Value(4)
          Return v35
        ");
    }

    #[test]
    fn test_fold_fixnum_add() {
        eval("
            def test
              1 + 2 + 3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v33:Fixnum[6] = Const Value(6)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_fold_fixnum_add_zero() {
        eval("
            def test(n)
              0 + n + 0
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v10, Fixnum
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_fold_fixnum_sub() {
        eval("
            def test
              5 - 3 - 1
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v33:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_fold_fixnum_sub_large_negative_result() {
        eval("
            def test
              0 - 1073741825
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[1073741825] = Const Value(1073741825)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v24:Fixnum[-1073741825] = Const Value(-1073741825)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_no_fold_fixnum_add_overflow() {
        eval(&format!("
            def test
              {RUBY_FIXNUM_MAX} + 1
            end
        "));
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
          v10:Fixnum[4611686018427387903] = Const Value(4611686018427387903)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v23:Fixnum = FixnumAdd v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_no_fold_fixnum_sub_underflow() {
        eval(&format!("
            def test
              {RUBY_FIXNUM_MIN} - 1
            end
        "));
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
          v10:Fixnum[-4611686018427387904] = Const Value(-4611686018427387904)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v23:Fixnum = FixnumSub v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_no_fold_fixnum_mult_overflow() {
        eval(&format!("
            def test
              {RUBY_FIXNUM_MAX} * 2
            end
        "));
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
          v10:Fixnum[4611686018427387903] = Const Value(4611686018427387903)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v23:Fixnum = FixnumMult v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_sub_zero() {
        eval("
            def test(n)
              n - 0
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1008, -@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_fixnum_mult() {
        eval("
            def test
              6 * 7
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[6] = Const Value(6)
          v12:Fixnum[7] = Const Value(7)
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v24:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_mult_zero() {
        eval("
            def test(n)
              0 * n + n * 0
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1008, *@0x1010, cme:0x1018)
          v36:Fixnum = GuardType v10, Fixnum
          v46:Fixnum[0] = Const Value(0)
          v47:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1040, cme:0x1048)
          CheckInterrupts
          Return v47
        ");
    }

    #[test]
    fn test_fold_fixnum_mult_one() {
        eval("
            def test(n)
              1 * n + n * 1
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, *@0x1010, cme:0x1018)
          v36:Fixnum = GuardType v10, Fixnum
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1040, cme:0x1048)
          v45:Fixnum = FixnumAdd v36, v36
          CheckInterrupts
          Return v45
        ");
    }

    #[test]
    fn test_fold_fixnum_div() {
        eval("
            def test
              7 / 3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[7] = Const Value(7)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, /@0x1008, cme:0x1010)
          v24:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_dont_fold_fixnum_div_zero() {
        eval("
            def test
              7 / 0
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[7] = Const Value(7)
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, /@0x1008, cme:0x1010)
          v23:Integer = FixnumDiv v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_div_negative() {
        eval("
            def test
              7 / -3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[7] = Const Value(7)
          v12:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Integer@0x1000, /@0x1008, cme:0x1010)
          v24:Fixnum[-3] = Const Value(-3)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_dont_fold_fixnum_div_negative_one_overflow() {
        eval(&format!("
            def test
              {RUBY_FIXNUM_MIN} / -1
            end
        "));
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
          v10:Fixnum[-4611686018427387904] = Const Value(-4611686018427387904)
          v12:Fixnum[-1] = Const Value(-1)
          PatchPoint MethodRedefined(Integer@0x1000, /@0x1008, cme:0x1010)
          v23:Integer = FixnumDiv v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_div_one() {
        eval("
            def test(n)
              n / 1
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, /@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_zero_by_zero() {
        eval("
            def test
              0 % 0
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v23:Fixnum = FixnumMod v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_non_zero_by_zero() {
        eval("
            def test
              11 % 0
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[11] = Const Value(11)
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v23:Fixnum = FixnumMod v10, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_zero_by_non_zero() {
        eval("
            def test
              0 % 11
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[11] = Const Value(11)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v24:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_mod() {
        eval("
            def test
              11 % 3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[11] = Const Value(11)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v24:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative_numerator() {
        eval("
            def test
              -7 % 3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[-7] = Const Value(-7)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v24:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative_denominator() {
        eval("
            def test
              7 % -3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[7] = Const Value(7)
          v12:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v24:Fixnum[-2] = Const Value(-2)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative() {
        eval("
            def test
              -7 % -3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[-7] = Const Value(-7)
          v12:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v24:Fixnum[-1] = Const Value(-1)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_xor() {
        eval("
            def test
              2 ^ 5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v23:Fixnum[7] = Const Value(7)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_xor_same_negative_number() {
        eval("
            def test
              123 ^ -123
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[123] = Const Value(123)
          v12:Fixnum[-123] = Const Value(-123)
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v23:Fixnum[-2] = Const Value(-2)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_fixnum_and() {
        eval("
            def test
              4 & -7
            end
        ");

        assert_snapshot!(inspect("test"), @"0");
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
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[-7] = Const Value(-7)
          PatchPoint MethodRedefined(Integer@0x1000, &@0x1008, cme:0x1010)
          v25:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_and_with_negative_self() {
        eval("
            def test
              -4 & 7
            end
        ");

        assert_snapshot!(inspect("test"), @"4");
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
          v10:Fixnum[-4] = Const Value(-4)
          v12:Fixnum[7] = Const Value(7)
          PatchPoint MethodRedefined(Integer@0x1000, &@0x1008, cme:0x1010)
          v25:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_or() {
        eval("
            def test
              4 | 1
            end
        ");

        assert_snapshot!(inspect("test"), @"5");
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
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, |@0x1008, cme:0x1010)
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_or_with_negative_self() {
        eval("
            def test
              -4 | 1
            end
        ");

        assert_snapshot!(inspect("test"), @"-3");
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
          v10:Fixnum[-4] = Const Value(-4)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, |@0x1008, cme:0x1010)
          v25:Fixnum[-3] = Const Value(-3)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_or_with_negative_other() {
        eval("
            def test
              4 | -1
            end
        ");

        assert_snapshot!(inspect("test"), @"-1");
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
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[-1] = Const Value(-1)
          PatchPoint MethodRedefined(Integer@0x1000, |@0x1008, cme:0x1010)
          v25:Fixnum[-1] = Const Value(-1)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_less() {
        eval("
            def test
              if 1 < 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_less_equal() {
        eval("
            def test
              if 1 <= 2 && 2 <= 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <=@0x1008, cme:0x1010)
          v58:TrueClass = Const Value(true)
          CheckInterrupts
          v37:Fixnum[3] = Const Value(3)
          Return v37
        ");
    }

    #[test]
    fn test_fold_fixnum_greater() {
        eval("
            def test
              if 2 > 1
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_greater_equal() {
        eval("
            def test
              if 2 >= 1 && 2 >= 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >=@0x1008, cme:0x1010)
          v58:TrueClass = Const Value(true)
          CheckInterrupts
          v37:Fixnum[3] = Const Value(3)
          Return v37
        ");
    }

    #[test]
    fn test_fold_fixnum_eq_false() {
        eval("
            def test
              if 1 == 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v42:FalseClass = Const Value(false)
          CheckInterrupts
          v33:Fixnum[4] = Const Value(4)
          Return v33
        ");
    }

    #[test]
    fn test_fold_fixnum_eq_true() {
        eval("
            def test
              if 2 == 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_neq_true() {
        eval("
            def test
              if 1 != 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v43:TrueClass = Const Value(true)
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_neq_false() {
        eval("
            def test
              if 2 != 2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v43:FalseClass = Const Value(false)
          CheckInterrupts
          v33:Fixnum[4] = Const Value(4)
          Return v33
        ");
    }

    #[test]
    fn test_fold_unbox_fixnum() {
        eval("
            def test(arr) = arr[0]
            test([1,2,3])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v27:ArrayExact = GuardType v10, ArrayExact recompile
          v35:CInt64[0] = Const CInt64(0)
          v29:CInt64 = ArrayLength v27
          v30:CInt64[0] = GuardLess v35, v29
          v34:BasicObject = ArrayAref v27, v30
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_fold_guard_greater_eq() {
        eval("
            def test(arr) = arr[0]
            test([1,2,3])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v27:ArrayExact = GuardType v10, ArrayExact recompile
          v35:CInt64[0] = Const CInt64(0)
          v29:CInt64 = ArrayLength v27
          v30:CInt64[0] = GuardLess v35, v29
          v34:BasicObject = ArrayAref v27, v30
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_fold_guard_greater_eq_side_exit() {
        eval(r##"
            def test = [4,5,6].freeze[-10]
        "##);
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
          v13:Fixnum[-10] = Const Value(-10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v32:CInt64[-10] = Const CInt64(-10)
          v33:CInt64[3] = Const CInt64(3)
          v28:CInt64 = AdjustBounds v32, v33
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64 = GuardGreaterEq v28, v29
          v31:BasicObject = ArrayAref v11, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn neq_with_side_effect_not_elided () {
        let result = eval("
            class CustomEq
              attr_reader :count

              def ==(o)
                @count = @count.to_i + 1
                self.equal?(o)
              end
            end

            def test(object)
              # intentionally unused, but also can't assign to underscore
              object != object
              nil
            end

            custom = CustomEq.new
            test(custom)
            test(custom)

            custom.count
        ");
        assert_eq!(VALUE::fixnum_from_usize(2), result);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:13:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :object@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :object@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(CustomEq@0x1008)
          PatchPoint MethodRedefined(CustomEq@0x1008, !=@0x1010, cme:0x1018)
          v30:ObjectSubclass[class_exact:CustomEq] = GuardType v10, ObjectSubclass[class_exact:CustomEq] recompile
          v31:BoolExact = CCallWithFrame v30, :BasicObject#!=@0x1040, v30
          v21:NilClass = Const Value(nil)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_replace_guard_if_known_fixnum() {
        eval("
            def test(a)
              a + 1
            end
            test(2); test(3)
        ");
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
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:Fixnum = FixnumAdd v26, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_param_forms_get_bb_param() {
        eval("
            def rest(*array) = array
            def kw(k:) = k
            def kw_rest(**k) = k
            def post(*rest, post) = post
            def block(&b) = nil
        ");
        assert_snapshot!(hir_strings!("rest", "kw", "kw_rest", "block", "post"), @"
        fn rest@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:ArrayExact = LoadField v2, :array@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :array@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          Return v10

        fn kw@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :k@0x1000
          v4:BasicObject = LoadField v2, :<empty>@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :k@1
          v9:CPtr = GetEP 0
          v10:BasicObject = LoadField v9, :<empty>@0x1002
          Jump bb3(v7, v8, v10)
        bb3(v12:BasicObject, v13:BasicObject, v14:BasicObject):
          CheckInterrupts
          Return v13

        fn kw_rest@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :k@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :k@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          Return v10

        fn block@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :b@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :b@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:NilClass = Const Value(nil)
          CheckInterrupts
          Return v14

        fn post@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:ArrayExact = LoadField v2, :rest@0x1000
          v4:BasicObject = LoadField v2, :post@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :rest@1
          v9:BasicObject = LoadArg :post@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_optimize_send_without_block_to_aliased_iseq() {
        eval("
            def foo = 1
            alias bar foo
            alias baz bar
            def test = baz
            test; test
        ");
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
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_optimize_send_without_block_to_aliased_cfunc() {
        eval("
            alias bar itself
            alias baz bar
            def test = baz
            test; test
        ");
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
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_nonparam_local_return() {
        eval("
            def foo(a)
              if false
                x = nil
              end
              x
            end
            def test = foo(1)
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:8:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v32:NilClass = Const Value(nil)
          PushInlineFrame v20 (0x1038), v11
          CheckInterrupts
          PopInlineFrame
          Return v32
        ");
    }

    #[test]
    fn test_optimize_send_to_aliased_cfunc() {
        eval("
            class C < Array
              alias fun_new_map map
            end
            def test(o) = o.fun_new_map {|e| e }
            test C.new; test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, fun_new_map@0x1010, cme:0x1018)
          v25:ArraySubclass[class_exact:C] = GuardType v10, ArraySubclass[class_exact:C] recompile
          v26:BasicObject = SendDirect v25, 0x1040, :fun_new_map (0x1050)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_optimize_send_to_aliased_cfunc_from_module() {
        eval("
            class C
              include Enumerable
              def each; yield 1; end
              alias bar map
            end
            def test(o) = o.bar { |x| x }
            test C.new; test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, bar@0x1010, cme:0x1018)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v27:BasicObject = CCallWithFrame v26, :Enumerable#bar@0x1040, block=0x1048
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
        ");
    }

    // Regression test: when specialized_instruction is disabled, the compiler
    // doesn't convert `send` to `opt_send_without_block`, so a no-block call
    // reaches ZJIT as `YARVINSN_send` with a null blockiseq. This becomes
    // `Send { blockiseq: Some(null_ptr) }` which must be normalized to None in
    // reduce_send_to_ccall, otherwise CCallWithFrame gens wrong block handler.
    #[test]
    fn test_send_to_cfunc_without_specialized_instruction() {
        eval_with_options("
            def test(a) = a.length
            test([1,2,3]); test([1,2,3])
        ", "{ specialized_instruction: false }");
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
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, length@0x1010, cme:0x1018)
          v24:ArrayExact = GuardType v10, ArrayExact recompile
          v25:CInt64 = ArrayLength v24
          v26:Fixnum = BoxFixnum v25
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_optimize_nonexistent_top_level_call() {
        eval("
            def foo
            end
            def test
              foo
            end
            test; test
            undef :foo
        ");
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
          v11:BasicObject = Send v6, :foo # SendFallbackReason: SendWithoutBlock: unsupported method type Null
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_call_with_overloaded_cme() {
        eval("
            def test
              Integer(3)
            end
            test; test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, Integer@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v20 (0x1038), v11
          v27:BasicObject = InvokeBuiltin rb_f_integer1, v20, v11
          CheckInterrupts
          PopInlineFrame
          Return v27
        ");
    }

    #[test]
    fn test_optimize_call_with_args() {
        eval("
            def foo(a, b) = []
            def test
              foo 1, 2
            end
            test; test
        ");
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v22 (0x1038), v11, v13
          v30:ArrayExact = NewArray
          CheckInterrupts
          PopInlineFrame
          Return v30
        ");
    }

    #[test]
    fn test_optimize_send_no_optionals_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v18 (0x1038)
          v25:Fixnum[1] = Const Value(1)
          v33:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1048, cme:0x1050)
          v60:Fixnum[3] = Const Value(3)
          CheckInterrupts
          PopInlineFrame
          Return v60
        ");
    }

    #[test]
    fn test_optimize_send_one_optional_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo 3
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v20 (0x1038), v11
          v35:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1048, cme:0x1050)
          v61:Fixnum[5] = Const Value(5)
          CheckInterrupts
          PopInlineFrame
          Return v61
        ");
    }

    #[test]
    fn test_optimize_send_all_optionals_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo 3, 4
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[4] = Const Value(4)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v22 (0x1038), v11, v13
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1048, cme:0x1050)
          v62:Fixnum[7] = Const Value(7)
          CheckInterrupts
          PopInlineFrame
          Return v62
        ");
    }

    #[test]
    fn test_call_with_correct_and_too_many_args_for_method() {
        eval("
            def target(a = 1, b = 2, c = 3, d = 4) = [a, b, c, d]
            def test = [target(), target(10, 20, 30), begin; target(10, 20, 30, 40, 50) rescue ArgumentError; end]
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v44:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v44 (0x1038)
          v56:Fixnum[1] = Const Value(1)
          v66:Fixnum[2] = Const Value(2)
          v76:Fixnum[3] = Const Value(3)
          v86:Fixnum[4] = Const Value(4)
          v101:ArrayExact = NewArray v56, v66, v76, v86
          CheckInterrupts
          PopInlineFrame
          v14:Fixnum[10] = Const Value(10)
          v16:Fixnum[20] = Const Value(20)
          v18:Fixnum[30] = Const Value(30)
          PushInlineFrame v44 (0x1038), v14, v16, v18
          v151:Fixnum[4] = Const Value(4)
          v166:ArrayExact = NewArray v14, v16, v18, v151
          PopInlineFrame
          v24:Fixnum[10] = Const Value(10)
          v26:Fixnum[20] = Const Value(20)
          v28:Fixnum[30] = Const Value(30)
          v30:Fixnum[40] = Const Value(40)
          v32:Fixnum[50] = Const Value(50)
          v34:BasicObject = Send v44, :target, v24, v26, v28, v30, v32 # SendFallbackReason: Argument count does not match parameter count
          v37:ArrayExact = NewArray v101, v166, v34
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_optimize_variadic_ccall() {
        eval("
            def test
              puts 'Hello'
            end
            test; test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          PatchPoint MethodRedefined(Object@0x1008, puts@0x1010, cme:0x1018)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v23:BasicObject = CCallVariadic v22, :Kernel#puts@0x1040, v12
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_optimize_fixnum_add_if_redefined() {
        eval("
            class Integer
              def +(other)
                100
              end
            end
            def test(a, b) = a + b
            test(1,2); test(3,4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
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
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v12, Fixnum recompile
          v28:Fixnum[100] = Const Value(100)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_both_profiled() {
        eval("
            def test(a, b) = a + b
            test(1,2); test(3,4)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAdd v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_left_profiled() {
        eval("
            def test(a) = a + 1
            test(1); test(3)
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
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:Fixnum = FixnumAdd v26, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_right_profiled() {
        eval("
            def test(a) = 1 + a
            test(1); test(3)
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
          v14:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v10, Fixnum
          v28:Fixnum = FixnumAdd v14, v27
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn integer_aref_with_fixnum_emits_fixnum_aref() {
        eval("
            def test(a, b) = a[b]
            test(3, 4)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, []@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAref v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn elide_fixnum_aref() {
        eval("
            def test
              1[2]
              5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          v19:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn do_not_optimize_integer_aref_with_too_many_args() {
        eval("
            def test = 1[2, 3]
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          v14:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          v24:BasicObject = CCallVariadic v10, :Integer#[]@0x1038, v12, v14
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn do_not_optimize_integer_aref_with_non_fixnum() {
        eval(r#"
            def test = 1["x"]
        "#);
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
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:StringExact = StringCopy v12
          PatchPoint MethodRedefined(Integer@0x1008, []@0x1010, cme:0x1018)
          v24:BasicObject = CCallVariadic v10, :Integer#[]@0x1040, v13
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_both_profiled() {
        eval("
            def test(a, b) = a < b
            test(1,2); test(3,4)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, <@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:BoolExact = FixnumLt v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_left_profiled() {
        eval("
            def test(a) = a < 1
            test(1); test(3)
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
          PatchPoint MethodRedefined(Integer@0x1008, <@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:BoolExact = FixnumLt v26, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_right_profiled() {
        eval("
            def test(a) = 1 < a
            test(1); test(3)
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
          v14:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, <@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v10, Fixnum
          v28:BoolExact = FixnumLt v14, v27
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_new_range_fixnum_inclusive_literals() {
        eval("
            def test()
              a = 2
              (1..a)
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:Fixnum[2] = Const Value(2)
          v17:Fixnum[1] = Const Value(1)
          v26:RangeExact = NewRangeFixnum v17 NewRangeInclusive v13
          CheckInterrupts
          Return v26
        ");
    }


    #[test]
    fn test_optimize_new_range_fixnum_exclusive_literals() {
        eval("
            def test()
              a = 2
              (1...a)
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:Fixnum[2] = Const Value(2)
          v17:Fixnum[1] = Const Value(1)
          v26:RangeExact = NewRangeFixnum v17 NewRangeExclusive v13
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_optimize_new_range_fixnum_inclusive_high_guarded() {
        eval("
            def test(a)
              (1..a)
            end
            test(2); test(3)
        ");
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
          v14:Fixnum[1] = Const Value(1)
          v23:Fixnum = GuardType v10, Fixnum
          v24:RangeExact = NewRangeFixnum v14 NewRangeInclusive v23
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_new_range_fixnum_exclusive_high_guarded() {
        eval("
            def test(a)
              (1...a)
            end
            test(2); test(3)
        ");
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
          v14:Fixnum[1] = Const Value(1)
          v23:Fixnum = GuardType v10, Fixnum
          v24:RangeExact = NewRangeFixnum v14 NewRangeExclusive v23
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_new_range_fixnum_inclusive_low_guarded() {
        eval("
            def test(a)
              (a..10)
            end
            test(2); test(3)
        ");
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
          v15:Fixnum[10] = Const Value(10)
          v23:Fixnum = GuardType v10, Fixnum
          v24:RangeExact = NewRangeFixnum v23 NewRangeInclusive v15
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_new_range_fixnum_exclusive_low_guarded() {
        eval("
            def test(a)
              (a...10)
            end
            test(2); test(3)
        ");
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
          v15:Fixnum[10] = Const Value(10)
          v23:Fixnum = GuardType v10, Fixnum
          v24:RangeExact = NewRangeFixnum v23 NewRangeExclusive v15
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_do_not_eliminate_comment() {
        let mut function = Function::new(std::ptr::null());
        let block = function.entry_block;

        let comment = function.push_comment(block, "diagnostic".to_string());
        let dead_const = function.push_insn(block, Insn::Const { val: Const::CBool(false) });
        let return_val = function.push_insn(block, Insn::Const { val: Const::CBool(true) });
        function.push_insn(block, Insn::Return { val: return_val });
        function.seal_entries();

        function.eliminate_dead_code();

        let insns = &function.blocks[block.0].insns;
        assert!(insns.contains(&comment));
        assert!(!insns.contains(&dead_const));
    }

    // A GuardType whose value type is disjoint from the guard type can never pass, so every
    // execution side-exits there. fold_constants should replace the guard with an unconditional
    // SideExit and drop the now-unreachable instructions that follow.
    #[test]
    fn test_fold_guard_type_that_can_never_pass_into_side_exit() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;

        let state = function.push_insn(entry, Insn::Snapshot { state: Box::new(FrameState::new(std::ptr::null())) });
        // A nil constant is a NilClass, which is disjoint from Fixnum, so the guard below can
        // never pass and the optimizer infers its result as Empty.
        let nil = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        let guard = function.push_insn(entry, Insn::GuardType { val: nil, guard_type: types::Fixnum, state, recompile: None });
        function.push_insn(entry, Insn::StoreField { recv: nil, id: FieldName::len, offset: 0, val: guard });
        function.push_insn(entry, Insn::Return { val: guard });
        function.seal_entries();

        function.infer_types();
        function.fold_constants();

        let insns: Vec<Insn> = function.blocks[entry.0].insns.iter().map(|&id| function.find(id)).collect();
        assert!(
            insns.iter().any(|insn| matches!(insn, Insn::SideExit { .. })),
            "expected the always-failing guard to be folded into a SideExit, got {insns:?}",
        );
        assert!(
            !insns.iter().any(|insn| matches!(insn, Insn::GuardType { .. })),
            "the always-failing GuardType should have been removed, got {insns:?}",
        );
        assert!(
            !insns.iter().any(|insn| matches!(insn, Insn::StoreField { .. } | Insn::Return { .. })),
            "instructions after the unconditional SideExit are unreachable and should have been dropped, got {insns:?}",
        );
    }

    #[test]
    fn test_eliminate_new_array() {
        eval("
            def test()
              c = []
              5
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:ArrayExact = NewArray
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_opt_aref_array() {
        eval("
            arr = [1,2,3]
            def test(arr) = arr[0]
            test(arr)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v27:ArrayExact = GuardType v10, ArrayExact recompile
          v35:CInt64[0] = Const CInt64(0)
          v29:CInt64 = ArrayLength v27
          v30:CInt64[0] = GuardLess v35, v29
          v34:BasicObject = ArrayAref v27, v30
          CheckInterrupts
          Return v34
        ");
        assert_snapshot!(inspect("test [1,2,3]"), @"1");
    }

    #[test]
    fn test_opt_aref_hash() {
        eval("
            arr = {0 => 4}
            def test(arr) = arr[0]
            test(arr)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          v27:HashExact = GuardType v10, HashExact recompile
          v28:BasicObject = HashAref v27, v15
          CheckInterrupts
          Return v28
        ");
        assert_snapshot!(inspect("test({0 => 4})"), @"4");
    }

    #[test]
    fn test_eliminate_new_range() {
        eval("
            def test()
              c = (1..2)
              5
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:RangeExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_do_not_eliminate_new_range_non_fixnum() {
        eval("
            def test()
              _ = (-'a'..'b')
              0
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          v14:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v17:StringExact = StringCopy v16
          v19:RangeExact = NewRange v14 NewRangeInclusive v17
          PatchPoint NoEPEscape(test)
          v25:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_eliminate_new_array_with_elements() {
        eval("
            def test(a)
              c = [a]
              5
            end
            test(1); test(2)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :a@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :a@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v18:ArrayExact = NewArray v12
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_eliminate_new_hash() {
        eval("
            def test()
              c = {}
              5
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v19:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_no_eliminate_new_hash_with_elements() {
        eval("
            def test(aval, bval)
              c = {a: aval, b: bval}
              5
            end
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :aval@0x1000
          v4:BasicObject = LoadField v2, :bval@0x1001
          v5:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :aval@1
          v10:BasicObject = LoadArg :bval@2
          v11:NilClass = Const Value(nil)
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:NilClass):
          v20:StaticSymbol[:a] = Const Value(VALUE(0x1008))
          v23:StaticSymbol[:b] = Const Value(VALUE(0x1010))
          v26:HashExact = NewHash v20: v14, v23: v15
          PatchPoint NoEPEscape(test)
          v32:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_eliminate_array_dup() {
        eval("
            def test
              c = [1, 2]
              5
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:ArrayExact = ArrayDup v13
          v18:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_eliminate_hash_dup() {
        eval("
            def test
              c = {a: 1, b: 2}
              5
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:HashExact = HashDup v13
          v18:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_eliminate_putself() {
        eval("
            def test()
              c = self
              5
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v16:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_eliminate_string_copy() {
        eval(r#"
            def test()
              c = "abc"
              5
            end
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @"
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
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:StringExact = StringCopy v13
          v18:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_eliminate_fixnum_add() {
        eval("
            def test(a, b)
              a + b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_sub() {
        eval("
            def test(a, b)
              a - b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, -@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_mul() {
        eval("
            def test(a, b)
              a * b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, *@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_do_not_eliminate_fixnum_div() {
        eval("
            def test(a, b)
              a / b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, /@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v34:Integer = FixnumDiv v32, v33
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_do_not_eliminate_fixnum_mod() {
        eval("
            def test(a, b)
              a % b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, %@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v34:Fixnum = FixnumMod v32, v33
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_lt() {
        eval("
            def test(a, b)
              a < b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, <@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_le() {
        eval("
            def test(a, b)
              a <= b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, <=@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_gt() {
        eval("
            def test(a, b)
              a > b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, >@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_ge() {
        eval("
            def test(a, b)
              a >= b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, >=@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_eq() {
        eval("
            def test(a, b)
              a == b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, ==@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          v33:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_eliminate_fixnum_neq() {
        eval("
            def test(a, b)
              a != b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Integer@0x1008, !=@0x1010, cme:0x1018)
          v32:Fixnum = GuardType v12, Fixnum recompile
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v34:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_do_not_eliminate_get_constant_path() {
        eval("
            def test()
              C
              5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:BasicObject = GetConstantPath 0x1000
          v14:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_do_not_eliminate_getconstant() {
        eval("
            def test(klass)
              klass::ARGV
              5
            end
        ");
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
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn kernel_itself_const() {
        eval("
            def test(x) = x.itself
            test(0) # profile
            test(1)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, itself@0x1010, cme:0x1018)
          v23:Fixnum = GuardType v10, Fixnum recompile
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn kernel_itself_known_type() {
        eval("
            def test = [].itself
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn eliminate_kernel_itself() {
        eval("
            def test
              x = [].itself
              1
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          PatchPoint NoEPEscape(test)
          v21:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn eliminate_module_name() {
        eval("
            module M; end
            def test
              x = M.name
              1
            end
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, M)
          v15:ModuleExact[M@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, name@0x1018, cme:0x1020)
          v33:StringExact|NilClass = CCall v15, :Module#name@0x1048
          PatchPoint NoEPEscape(test)
          v23:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn eliminate_array_length() {
        eval("
            def test
              [].length
              5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn normal_class_type_inference() {
        eval("
            class C; end
            def test = C
            test # Warm the constant cache
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v12:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn core_classes_type_inference() {
        eval("
            def test = [String, Class, Module, BasicObject]
            test # Warm the constant cache
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v12:ClassSubclass[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Class)
          v16:ClassSubclass[Class@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint StableConstantNames(0x1020, Module)
          v20:ClassSubclass[Module@0x1028] = Const Value(VALUE(0x1028))
          PatchPoint StableConstantNames(0x1030, BasicObject)
          v24:ClassSubclass[BasicObject@0x1038] = Const Value(VALUE(0x1038))
          v26:ArrayExact = NewArray v12, v16, v20, v24
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn module_instances_are_module_exact() {
        eval("
            def test = [Enumerable, Kernel]
            test # Warm the constant cache
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Enumerable)
          v12:ModuleExact[Enumerable@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Kernel)
          v16:ModuleSubclass[Kernel@0x1018] = Const Value(VALUE(0x1018))
          v18:ArrayExact = NewArray v12, v16
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn module_subclasses_are_not_module_exact() {
        eval("
            class ModuleSubclass < Module; end
            MY_MODULE = ModuleSubclass.new
            def test = MY_MODULE
            test # Warm the constant cache
        ");
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, MY_MODULE)
          v12:ModuleSubclass[MY_MODULE@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn eliminate_array_size() {
        eval("
            def test
              [].size
              5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn kernel_itself_argc_mismatch() {
        eval("
            def test = 1.itself(0)
            test rescue 0
            test rescue 0
        ");
        // Not specialized
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
          v12:Fixnum[0] = Const Value(0)
          v14:BasicObject = Send v10, :itself, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_inline_kernel_block_given_p() {
        eval("
            def test = block_given?
            test
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
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v20:CPtr = GetEP 0
          v21:BoolExact = IsBlockGiven v20
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_inline_kernel_block_given_p_in_block() {
        eval("
            TEST = proc { block_given? }
            TEST.call
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v20:FalseClass = Const Value(false)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_elide_kernel_block_given_p() {
        eval("
            def test
              block_given?
              5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v15:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn const_send_direct_integer() {
        eval("
            def test(x) = 1.zero?
        ");
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
          v14:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, zero?@0x1010, cme:0x1018)
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v14
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn class_known_send_direct_array() {
        eval("
            def test(x)
              a = [1,2,3]
              a.first
            end
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v17:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v18:ArrayExact = ArrayDup v17
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, first@0x1018, cme:0x1020)
          v31:BasicObject = InvokeBuiltin leaf <inline_expr>, v18
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn send_direct_to_module() {
        eval("
            module M; end
            def test = M.class
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, M)
          v12:ModuleExact[M@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, class@0x1018, cme:0x1020)
          v23:ClassSubclass[Module@0x1010] = Const Value(VALUE(0x1010))
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_send_to_instance_method() {
        eval("
            class C
              def foo = []
            end

            def test(c) = c.foo
            c = C.new
            test c
            test c
        ");

        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :c@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :c@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PushInlineFrame v23 (0x1040)
          v29:ArrayExact = NewArray
          CheckInterrupts
          PopInlineFrame
          Return v29
        ");
    }

    #[test]
    fn test_send_iseq_with_block() {
        let result = eval("
            def foo(a, b, &block) = block.call(a, b)
            def test = foo(1, 2) { |a, b| a + b }
            test
            test
        ");
        assert_eq!(VALUE::fixnum_from_usize(3), result);
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v51:NilClass = Const Value(nil)
          PushInlineFrame v22 (0x1038), v11, v13
          v33:CPtr = GetEP 0
          v34:CUInt64 = LoadField v33, :VM_ENV_DATA_INDEX_FLAGS@0x1040
          v35:CBool = IsBlockParamModified v34
          CondBranch v35, bb6(), bb7()
        bb6():
          v37:BasicObject = LoadField v33, :block@0x1041
          Jump bb8(v37, v37)
        bb7():
          v39:CInt64 = LoadField v33, :VM_ENV_DATA_INDEX_SPECVAL@0x1042
          v40:CInt64 = GuardAnyBitSet v39, CUInt64(1) recompile
          v41:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1048))
          Jump bb8(v41, v51)
        bb8(v31:BasicObject, v32:BasicObject):
          v46:BasicObject = Send v31, :call, v11, v13 # SendFallbackReason: SendWithoutBlock: unsupported optimized method type BlockCall
          CheckInterrupts
          PopInlineFrame
          Return v46
        ");
    }

    #[test]
    fn reload_local_across_send() {
        eval("
            def foo(&block) = 1
            def test
              a = 1
              foo {|| a = 2 }
              a
            end
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v34:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v8, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v35:Fixnum[1] = Const Value(1)
          PatchPoint NoEPEscape(test)
          v21:CPtr = LoadSP
          v22:BasicObject = LoadField v21, :a@0x1038
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn reload_local_across_send_after_ep_escape() {
        eval("
            def foo(&block) = 1
            def test
              a = 1
              lambda { a }
              foo {|| a = 2 }
              a
            end
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          v7:CPtr = GetEP 0
          StoreField v7, :a@0x1000, v6
          Jump bb3(v5, v6)
        bb3(v10:BasicObject, v11:NilClass):
          v15:Fixnum[1] = Const Value(1)
          SetLocal :a, l0, EP@3, v15
          PatchPoint MethodRedefined(Object@0x1008, lambda@0x1010, cme:0x1018)
          v43:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v10, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v44:BasicObject = CCallWithFrame v43, :Kernel#lambda@0x1040, block=0x1048
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :a@0x1000
          PatchPoint MethodRedefined(Object@0x1008, foo@0x1050, cme:0x1058)
          v34:CPtr = GetEP 0
          v35:BasicObject = LoadField v34, :a@0x1000
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_rest() {
        enable_zjit_stats();
        eval("
            def foo(*args) = 1
            def test = foo 1
            test
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
          IncrCounterPtr
          Jump bb3(v4)
        bb3(v7:BasicObject):
          IncrCounter zjit_insn_count
          IncrCounter zjit_insn_count
          v14:Fixnum[1] = Const Value(1)
          IncrCounter zjit_insn_count
          IncrCounter complex_arg_pass_param_rest
          v17:BasicObject = Send v7, :foo, v14 # SendFallbackReason: Complex argument passing
          IncrCounter zjit_insn_count
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn specialize_call_to_post_param_iseq() {
        eval("
            def foo(opt=80, post) = post
            def test = foo(10)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v20 (0x1038), v11
          v27:Fixnum[80] = Const Value(80)
          CheckInterrupts
          PopInlineFrame
          Return v11
        ");
    }

    #[test]
    fn specialize_call_to_iseq_with_optional_between_required_params() {
        let result = eval("
            def foo(lead, opt=80, post) = lead + opt + post
            def test = foo(10, 20)
            test
            test
        ");
        assert_eq!(VALUE::fixnum_from_usize(110), result);
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
          v11:Fixnum[10] = Const Value(10)
          v13:Fixnum[20] = Const Value(20)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v22 (0x1038), v11, v13
          v30:Fixnum[80] = Const Value(80)
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1048, cme:0x1050)
          v66:Fixnum[110] = Const Value(110)
          CheckInterrupts
          PopInlineFrame
          Return v66
        ");
    }

    #[test]
    fn specialize_call_to_iseq_with_multiple_required_kw() {
        eval("
            def foo(a:, b:) = [a, b]
            def test = foo(a: 1, b: 2)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v38:Fixnum[0] = Const Value(0)
          PushInlineFrame v22 (0x1038), v11, v13
          v33:ArrayExact = NewArray v11, v13
          CheckInterrupts
          PopInlineFrame
          Return v33
        ");
    }

    #[test]
    fn specialize_call_to_iseq_with_required_kw_reorder() {
        eval("
            def foo(a:, b:, c:) = [a, b, c]
            def test = foo(c: 3, a: 1, b: 2)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[1] = Const Value(1)
          v15:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v43:Fixnum[0] = Const Value(0)
          PushInlineFrame v25 (0x1038), v13, v15, v11
          v38:ArrayExact = NewArray v13, v15, v11
          CheckInterrupts
          PopInlineFrame
          Return v38
        ");
    }

    #[test]
    fn specialize_call_to_iseq_with_positional_and_required_kw_reorder() {
        eval("
            def foo(x, a:, b:) = [x, a, b]
            def test = foo(0, b: 2, a: 1)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v43:Fixnum[0] = Const Value(0)
          PushInlineFrame v25 (0x1038), v11, v15, v13
          v38:ArrayExact = NewArray v11, v15, v13
          CheckInterrupts
          PopInlineFrame
          Return v38
        ");
    }

    #[test]
    fn specialize_call_with_positional_and_optional_kw() {
        eval("
            def foo(x, a: 1) = [x, a]
            def test = foo(0, a: 2)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v38:Fixnum[0] = Const Value(0)
          PushInlineFrame v22 (0x1038), v11, v13
          v33:ArrayExact = NewArray v11, v13
          CheckInterrupts
          PopInlineFrame
          Return v33
        ");
    }

    #[test]
    fn specialize_call_with_pos_optional_and_req_kw() {
        eval("
            def foo(r, x = 2, a:, b:) = [x, a]
            def test = [foo(1, a: 3, b: 4), foo(1, 2, b: 4, a: 3)] # with and without the optional, change kw order
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          v15:Fixnum[4] = Const Value(4)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v37:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v71:Fixnum[0] = Const Value(0)
          PushInlineFrame v37 (0x1038), v11, v13, v15
          v51:Fixnum[2] = Const Value(2)
          v65:ArrayExact = NewArray v51, v13
          CheckInterrupts
          PopInlineFrame
          v20:Fixnum[1] = Const Value(1)
          v22:Fixnum[2] = Const Value(2)
          v24:Fixnum[4] = Const Value(4)
          v26:Fixnum[3] = Const Value(3)
          v103:Fixnum[0] = Const Value(0)
          PushInlineFrame v37 (0x1038), v20, v22, v26, v24
          v98:ArrayExact = NewArray v22, v26
          PopInlineFrame
          v30:ArrayExact = NewArray v65, v98
          Return v30
        ");
    }

    #[test]
    fn specialize_call_with_pos_optional_and_kw_optional() {
        eval("
            def foo(r, x = 2, a:, b: 4) = [r, x, a, b]
            def test = [foo(1, a: 3), foo(1, 2, b: 40, a: 30)] # with and without the optionals
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          v34:Fixnum[4] = Const Value(4)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v37:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v73:Fixnum[0] = Const Value(0)
          PushInlineFrame v37 (0x1038), v11, v13, v34
          v51:Fixnum[2] = Const Value(2)
          v67:ArrayExact = NewArray v11, v51, v13, v34
          CheckInterrupts
          PopInlineFrame
          v18:Fixnum[1] = Const Value(1)
          v20:Fixnum[2] = Const Value(2)
          v22:Fixnum[40] = Const Value(40)
          v24:Fixnum[30] = Const Value(30)
          v107:Fixnum[0] = Const Value(0)
          PushInlineFrame v37 (0x1038), v18, v20, v24, v22
          v102:ArrayExact = NewArray v18, v20, v24, v22
          PopInlineFrame
          v28:ArrayExact = NewArray v67, v102
          Return v28
        ");
    }

    #[test]
    fn test_call_with_pos_optional_and_maybe_too_many_args() {
        eval("
            def target(a = 1, b = 2, c = 3, d = 4, e = 5, f:) = [a, b, c, d, e, f]
            def test = [target(f: 6), target(10, 20, 30, f: 6), target(10, 20, 30, 40, 50, f: 60)]
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[6] = Const Value(6)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v48:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v49:BasicObject = SendDirect v48, 0x1038, :target (0x1048), v11
          v16:Fixnum[10] = Const Value(10)
          v18:Fixnum[20] = Const Value(20)
          v20:Fixnum[30] = Const Value(30)
          v22:Fixnum[6] = Const Value(6)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v52:BasicObject = SendDirect v48, 0x1038, :target (0x1048), v16, v18, v20, v22
          v27:Fixnum[10] = Const Value(10)
          v29:Fixnum[20] = Const Value(20)
          v31:Fixnum[30] = Const Value(30)
          v33:Fixnum[40] = Const Value(40)
          v35:Fixnum[50] = Const Value(50)
          v37:Fixnum[60] = Const Value(60)
          v39:BasicObject = Send v48, :target, v27, v29, v31, v33, v35, v37 # SendFallbackReason: Too many arguments for LIR
          v41:ArrayExact = NewArray v49, v52, v39
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_send_call_to_iseq_with_optional_kw() {
        eval("
            def foo(a: 1) = a
            def test = foo(a: 2)
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v32:Fixnum[0] = Const Value(0)
          PushInlineFrame v20 (0x1038), v11
          CheckInterrupts
          PopInlineFrame
          Return v11
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_kwrest() {
        enable_zjit_stats();
        eval("
            def foo(**args) = 1
            def test = foo(a: 1)
            test
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
          IncrCounterPtr
          Jump bb3(v4)
        bb3(v7:BasicObject):
          IncrCounter zjit_insn_count
          IncrCounter zjit_insn_count
          v14:Fixnum[1] = Const Value(1)
          IncrCounter zjit_insn_count
          IncrCounter complex_arg_pass_param_kwrest
          v17:BasicObject = Send v7, :foo, v14 # SendFallbackReason: Complex argument passing
          IncrCounter zjit_insn_count
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_send_hash_to_kwarg_only_method() {
        eval(r#"
            def callee(a:) = a
            def test = callee({a: 1})
            begin; test; rescue ArgumentError; end
            begin; test; rescue ArgumentError; end
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
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:HashExact = HashDup v11
          v14:BasicObject = Send v6, :callee, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_send_hash_to_optional_kwarg_only_method() {
        eval(r#"
            def callee(a: nil) = a
            def test = callee({a: 1})
            begin; test; rescue ArgumentError; end
            begin; test; rescue ArgumentError; end
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
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:HashExact = HashDup v11
          v14:BasicObject = Send v6, :callee, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn specialize_call_to_iseq_with_optional_param_kw_using_default() {
        eval("
            def foo(int: 1) = int + 1
            def test = foo
            test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v17:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v37:Fixnum[0] = Const Value(0)
          PushInlineFrame v20 (0x1038), v17
          v29:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1048, cme:0x1050)
          v46:Fixnum[2] = Const Value(2)
          CheckInterrupts
          PopInlineFrame
          Return v46
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_call_kwsplat() {
        enable_zjit_stats();
        eval("
            def foo(a:) = a
            def test = foo(**{a: 1})
            test
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
          IncrCounterPtr
          Jump bb3(v4)
        bb3(v7:BasicObject):
          IncrCounter zjit_insn_count
          IncrCounter zjit_insn_count
          v14:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:HashExact = HashDup v14
          IncrCounter zjit_insn_count
          IncrCounter complex_arg_pass_caller_kw_splat
          v18:BasicObject = Send v7, :foo, v15 # SendFallbackReason: Complex argument passing
          IncrCounter zjit_insn_count
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_param_kwrest() {
        enable_zjit_stats();
        eval("
            def foo(**kwargs) = kwargs.keys
            def test = foo
            test
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
          IncrCounterPtr
          Jump bb3(v4)
        bb3(v7:BasicObject):
          IncrCounter zjit_insn_count
          IncrCounter zjit_insn_count
          IncrCounter complex_arg_pass_param_kwrest
          v14:BasicObject = Send v7, :foo # SendFallbackReason: Complex argument passing
          IncrCounter zjit_insn_count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn dont_optimize_ccall_with_kwarg() {
        eval("
            def test = sprintf('%s', a: 1)
            test
            test
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
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          v14:Fixnum[1] = Const Value(1)
          v16:BasicObject = Send v6, :sprintf, v12, v14 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn dont_optimize_ccall_with_block_and_kwarg() {
        eval("
            def test(s)
              a = []
              s.each_line(chomp: true) { |l| a << l }
              a
            end
            test %(a\nb\nc)
            test %()
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v17:ArrayExact = NewArray
          v22:TrueClass = Const Value(true)
          v24:BasicObject = Send v12, 0x1008, :each_line, v22 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn dont_replace_get_constant_path_with_empty_ic() {
        eval("
            def test = Kernel
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
          v10:BasicObject = GetConstantPath 0x1000
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn dont_replace_get_constant_path_with_invalidated_ic() {
        eval("
            def test = Kernel
            test
            Kernel = 5
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
          v10:BasicObject = GetConstantPath 0x1000
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn replace_get_constant_path_with_const() {
        eval("
            def test = Kernel
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Kernel)
          v12:ModuleSubclass[Kernel@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn replace_nested_get_constant_path_with_const() {
        eval("
            module Foo
              module Bar
                class C
                end
              end
            end
            def test = Foo::Bar::C
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:8:
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
          PatchPoint StableConstantNames(0x1000, Foo::Bar::C)
          v12:ClassSubclass[Foo::Bar::C@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_opt_new_no_initialize() {
        eval("
            class C; end
            def test = C.new
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v12:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v45:ObjectSubclass[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          CheckInterrupts
          Return v45
        ");
    }

    #[test]
    fn test_opt_new_initialize() {
        eval("
            class C
              def initialize x
                @x = x
              end
            end
            def test = C.new 1
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
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
          PatchPoint StableConstantNames(0x1000, C)
          v12:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          v17:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v48:ObjectSubclass[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          PushInlineFrame v48 (0x1068), v17
          v65:CShape = LoadField v48, :shape_id@0x1070
          v66:CShape[0x1071] = GuardBitEquals v65, CShape(0x1071) recompile
          StoreField v48, :@x@0x1072, v17
          WriteBarrier v48, v17
          v69:CShape[0x1073] = Const CShape(0x1073)
          StoreField v48, :shape_id@0x1070, v69
          CheckInterrupts
          PopInlineFrame
          Return v48
        ");
    }

    #[test]
    fn test_opt_new_object() {
        eval("
            def test = Object.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Object)
          v12:ClassSubclass[Object@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Object@0x1008, new@0x1009, cme:0x1010)
          v45:ObjectExact = ObjectAllocClass Object:VALUE(0x1008)
          PatchPoint NoSingletonClass(Object@0x1008)
          PatchPoint MethodRedefined(Object@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          CheckInterrupts
          Return v45
        ");
    }

    #[test]
    fn test_opt_new_basic_object() {
        eval("
            def test = BasicObject.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, BasicObject)
          v12:ClassSubclass[BasicObject@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(BasicObject@0x1008, new@0x1009, cme:0x1010)
          v45:BasicObjectExact = ObjectAllocClass BasicObject:VALUE(0x1008)
          PatchPoint NoSingletonClass(BasicObject@0x1008)
          PatchPoint MethodRedefined(BasicObject@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          CheckInterrupts
          Return v45
        ");
    }

    #[test]
    fn test_opt_new_hash() {
        eval("
            def test = Hash.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Hash)
          v12:ClassSubclass[Hash@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Hash@0x1008, new@0x1009, cme:0x1010)
          v45:HashExact = ObjectAllocClass Hash:VALUE(0x1008)
          v46:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, initialize@0x1038, cme:0x1040)
          v97:Fixnum[0] = Const Value(0)
          v98:NilClass = Const Value(nil)
          PushInlineFrame v45 (0x1068), v46
          v64:TrueClass = Const Value(true)
          v82:CPtr = GetEP 0
          v83:CUInt64 = LoadField v82, :VM_ENV_DATA_INDEX_FLAGS@0x1070
          v84:CBool = IsBlockParamModified v83
          CondBranch v84, bb11(), bb12()
        bb11():
          v86:BasicObject = LoadField v82, :block@0x1071
          Jump bb13(v86)
        bb12():
          v88:BasicObject = GetBlockParam :block, l0, EP@4
          Jump bb13(v88)
        bb13(v81:BasicObject):
          v91:BasicObject = InvokeBuiltin rb_hash_init, v45, v46, v64, v64, v81
          CheckInterrupts
          PopInlineFrame
          Return v45
        ");
        assert_snapshot!(inspect("test"), @"{}");
    }

    #[test]
    fn test_opt_new_array() {
        eval("
            def test = Array.new 1
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Array)
          v12:ClassSubclass[Array@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          v17:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1008, new@0x1009, cme:0x1010)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v56:BasicObject = CCallVariadic v12, :Array.new@0x1040, v17
          CheckInterrupts
          Return v56
        ");
    }

    #[test]
    fn test_opt_new_set() {
        eval("
            def test = Set.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Set)
          v12:ClassSubclass[Set@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Set@0x1008, new@0x1009, cme:0x1010)
          v19:HeapBasicObject = ObjectAlloc v12
          PatchPoint NoSingletonClass(Set@0x1008)
          PatchPoint MethodRedefined(Set@0x1008, initialize@0x1038, cme:0x1040)
          v48:SetExact = GuardType v19, SetExact recompile
          v49:BasicObject = CCallVariadic v48, :Set#initialize@0x1068
          CheckInterrupts
          Return v48
        ");
    }

    #[test]
    fn test_opt_new_string() {
        eval("
            def test = String.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v12:ClassSubclass[String@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(String@0x1008, new@0x1009, cme:0x1010)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v53:BasicObject = CCallVariadic v12, :String.new@0x1040
          CheckInterrupts
          Return v53
        ");
    }

    #[test]
    fn test_opt_new_regexp() {
        eval("
            def test = Regexp.new ''
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Regexp)
          v12:ClassSubclass[Regexp@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          v17:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v18:StringExact = StringCopy v17
          PatchPoint MethodRedefined(Regexp@0x1008, new@0x1018, cme:0x1020)
          v49:RegexpExact = ObjectAllocClass Regexp:VALUE(0x1008)
          PatchPoint NoSingletonClass(Regexp@0x1008)
          PatchPoint MethodRedefined(Regexp@0x1008, initialize@0x1048, cme:0x1050)
          v54:BasicObject = CCallVariadic v49, :Regexp#initialize@0x1078, v18
          CheckInterrupts
          Return v49
        ");
    }

    #[test]
    fn test_inline_class_allocate() {
        eval("
            class C; end
            def test = C.allocate
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v12:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Class@0x1010, allocate@0x1018, cme:0x1020)
          v23:ObjectSubclass[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_inline_class_allocate_with_args() {
        eval("
            class C; end
            def test = C.allocate(1)
            test rescue 0
            test rescue 0
        ");
        // Not specialized
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v12:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          v14:Fixnum[1] = Const Value(1)
          v16:BasicObject = Send v12, :allocate, v14 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_dont_inline_class_allocate_with_singleton_class() {
        eval("
            class C; end
            SC = C.singleton_class
            def test = SC.allocate
            test rescue 0
        ");
        // Not specialized: singleton classes are not leaf allocators
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, SC)
          v12:ClassSubclass[Class@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Class@0x1010, allocate@0x1018, cme:0x1020)
          v23:BasicObject = CCallWithFrame v12, :Class.allocate@0x1048
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_opt_length() {
        eval("
            def test(a,b) = [a,b].length
        ");
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
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, length@0x1010, cme:0x1018)
          v31:CInt64 = ArrayLength v19
          v32:Fixnum = BoxFixnum v31
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_opt_size() {
        eval("
            def test(a,b) = [a,b].size
        ");
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
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, size@0x1010, cme:0x1018)
          v31:CInt64 = ArrayLength v19
          v32:Fixnum = BoxFixnum v31
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_getblockparamproxy() {
        eval("
            def test(&block) = tap(&block)
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
          v17:CPtr = GetEP 0
          v18:CUInt64 = LoadField v17, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v19:CBool = IsBlockParamModified v18
          CondBranch v19, bb4(), bb5()
        bb4():
          v21:BasicObject = LoadField v17, :block@0x1002
          Jump bb6(v21, v21)
        bb5():
          v23:CInt64 = LoadField v17, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v24:CInt64 = GuardAnyBitSet v23, CUInt64(1) recompile
          v25:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v25, v10)
        bb6(v15:BasicObject, v16:BasicObject):
          SideExit NoProfileSend recompile
        ");
    }

    #[test]
    fn test_getblockparamproxy_proc() {
        eval("
            val = proc { 1 }
            def test(&block)
              0.then(&block)
            end
            test(&val)
        ");
        assert_contains_opcode("test", YARVINSN_getblockparamproxy);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          v14:Fixnum[0] = Const Value(0)
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:BasicObject = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v25:BasicObject = CCall v24, :rb_obj_is_proc@0x1008
          v26:TrueClass = GuardBitEquals v25, Value(true) recompile
          Jump bb6(v24, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v29:BasicObject = Send v14, &block, :then, v16 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_recompile_no_profile_getblockparamproxy() {
        eval("
            def test(flag, &block)
              if flag
                0.then(&block)
              else
                :skip
              end
            end
            test(false)
            test(false)
            test(true)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :flag@0x1000
          v4:BasicObject = LoadField v2, :block@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :flag@1
          v9:BasicObject = LoadArg :block@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          CheckInterrupts
          v19:CBool = Test v12
          v20:Falsy = RefineType v12, Falsy
          CondBranch v19, bb5(), bb4(v11, v20, v13)
        bb5():
          v22:Truthy = RefineType v12, Truthy
          v25:Fixnum[0] = Const Value(0)
          v29:CPtr = GetEP 0
          v30:CUInt64 = LoadField v29, :VM_ENV_DATA_INDEX_FLAGS@0x1002
          v31:CBool = IsBlockParamModified v30
          CondBranch v31, bb6(), bb7()
        bb6():
          v33:BasicObject = LoadField v29, :block@0x1003
          Jump bb8(v33, v33)
        bb7():
          v35:CInt64 = LoadField v29, :VM_ENV_DATA_INDEX_SPECVAL@0x1004
          v36:CInt64[0] = GuardBitEquals v35, CInt64(0) recompile
          v37:NilClass = Const Value(nil)
          Jump bb8(v37, v13)
        bb8(v27:BasicObject, v28:BasicObject):
          v40:BasicObject = Send v25, &block, :then, v27 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v40
        bb4(v45:BasicObject, v46:Falsy, v47:BasicObject):
          v51:StaticSymbol[:skip] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v51
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
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :block@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :block@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22)
        bb5():
          v24:BasicObject = GetBlockParam :block, l0, EP@4
          Jump bb6(v24)
        bb6(v17:BasicObject):
          v32:CPtr = GetEP 0
          v33:CUInt64 = LoadField v32, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v34:CBool = IsBlockParamModified v33
          CondBranch v34, bb7(), bb8()
        bb7():
          v36:BasicObject = LoadField v32, :block@0x1002
          Jump bb9(v36, v36)
        bb8():
          v38:CInt64 = LoadField v32, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v39:CInt64 = GuardAnyBitSet v38, CUInt64(1) recompile
          v40:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb9(v40, v17)
        bb9(v30:BasicObject, v31:BasicObject):
          SideExit NoProfileSend recompile
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
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:BasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:BasicObject, v9:NilClass):
          v14:CPtr = GetEP 1
          v15:CUInt64 = LoadField v14, :VM_ENV_DATA_INDEX_FLAGS@0x1000
          v16:CBool = IsBlockParamModified v15
          CondBranch v16, bb4(), bb5()
        bb4():
          v18:BasicObject = LoadField v14, :block@0x1001
          Jump bb6(v18)
        bb5():
          v20:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb6(v20)
        bb6(v13:BasicObject):
          v27:CPtr = GetEP 1
          v28:CUInt64 = LoadField v27, :VM_ENV_DATA_INDEX_FLAGS@0x1000
          v29:CBool = IsBlockParamModified v28
          CondBranch v29, bb7(), bb8()
        bb7():
          v31:BasicObject = LoadField v27, :block@0x1001
          Jump bb9(v31)
        bb8():
          v33:CInt64 = LoadField v27, :VM_ENV_DATA_INDEX_SPECVAL@0x1002
          v34:CInt64 = GuardAnyBitSet v33, CUInt64(1) recompile
          v35:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb9(v35)
        bb9(v26:BasicObject):
          SideExit NoProfileSend recompile
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
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :block@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :block@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:Fixnum[0] = Const Value(0)
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v25:CInt64[1] = Const CInt64(1)
          v26:CInt64 = IntAnd v24, v25
          v27:CBool = IsBitEqual v26, v25
          CondBranch v27, bb7(), bb9()
        bb7():
          v29:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v29, v10)
        bb9():
          v31:CInt64[0] = Const CInt64(0)
          v32:CBool = IsBitEqual v24, v31
          CondBranch v32, bb8(), bb10()
        bb8():
          v34:NilClass = Const Value(nil)
          Jump bb6(v34, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v38:BasicObject = Send v14, &block, :then, v16 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v38
        bb10():
          SideExit BlockParamProxyProfileNotCovered
        ");
    }

    #[test]
    fn test_getblockparamproxy_polymorphic_none_and_iseq_and_proc() {
        set_call_threshold(4);
        eval("
            val = proc { 3 }
            def test(&block)
              0.then(&block)
            end
            test
            test { 1 }
            test(&val)
        ");
        assert_contains_opcode("test", YARVINSN_getblockparamproxy);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          v14:Fixnum[0] = Const Value(0)
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v26:BasicObject = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v27:BasicObject = CCall v26, :rb_obj_is_proc@0x1008
          v28:TrueClass = Const Value(true)
          v29:CBool = IsBitEqual v27, v28
          CondBranch v29, bb7(), bb11()
        bb7():
          Jump bb6(v26, v10)
        bb11():
          v32:CInt64[0] = Const CInt64(0)
          v33:CBool = IsBitEqual v24, v32
          CondBranch v33, bb8(), bb12()
        bb8():
          v35:NilClass = Const Value(nil)
          Jump bb6(v35, v10)
        bb12():
          v37:CInt64[1] = Const CInt64(1)
          v38:CInt64 = IntAnd v24, v37
          v39:CBool = IsBitEqual v38, v37
          CondBranch v39, bb9(), bb13()
        bb9():
          v41:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1010))
          Jump bb6(v41, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v45:BasicObject = Send v14, &block, :then, v16 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v45
        bb13():
          SideExit BlockParamProxyProfileNotCovered
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
          v15:CPtr = GetEP 0
          v16:CUInt64 = LoadField v15, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v17:CBool = IsBlockParamModified v16
          CondBranch v17, bb4(), bb5()
        bb4():
          v19:BasicObject = LoadField v15, :block@0x1002
          Jump bb6(v19)
        bb5():
          v21:BasicObject = GetBlockParam :block, l0, EP@3
          Jump bb6(v21)
        bb6(v14:BasicObject):
          CheckInterrupts
          Return v14
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
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :block@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :block@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:NilClass = Const Value(nil)
          SetLocal :block, l0, EP@3, v14
          v18:CPtr = GetEP 0
          v19:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CInt64[512] = Const CInt64(512)
          v21:CInt64 = IntOr v19, v20
          StoreField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001, v21
          CheckInterrupts
          Return v14
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
    fn test_getinstancevariable() {
        eval("
            def test = @foo
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          SetIvar v6, :@foo, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_specialize_monomorphic_definedivar_true() {
        eval("
            @foo = 4
            def test = defined?(@foo)
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v11:CShape = LoadField v10, :shape_id@0x1000
          v12:CShape[0x1001] = GuardBitEquals v11, CShape(0x1001) recompile
          v13:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_specialize_monomorphic_definedivar_false() {
        eval("
            def test = defined?(@foo)
            test
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v11:CShape = LoadField v10, :shape_id@0x1000
          v12:CShape[0x1001] = GuardBitEquals v11, CShape(0x1001) recompile
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_specialize_proc_call() {
        eval("
            p = proc { |x| x + 1 }
            def test(p)
              p.call(1)
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :p@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Proc@0x1008)
          PatchPoint MethodRedefined(Proc@0x1008, call@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact:Proc] = GuardType v10, ObjectSubclass[class_exact:Proc] recompile
          v26:BasicObject = InvokeProc v25, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_proc_aref() {
        eval("
            p = proc { |x| x + 1 }
            def test(p)
              p[2]
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :p@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Proc@0x1008)
          PatchPoint MethodRedefined(Proc@0x1008, []@0x1010, cme:0x1018)
          v26:ObjectSubclass[class_exact:Proc] = GuardType v10, ObjectSubclass[class_exact:Proc] recompile
          v27:BasicObject = InvokeProc v26, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_specialize_proc_yield() {
        eval("
            p = proc { |x| x + 1 }
            def test(p)
              p.yield(3)
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :p@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Proc@0x1008)
          PatchPoint MethodRedefined(Proc@0x1008, yield@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact:Proc] = GuardType v10, ObjectSubclass[class_exact:Proc] recompile
          v26:BasicObject = InvokeProc v25, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_proc_eqq() {
        eval("
            p = proc { |x| x > 0 }
            def test(p)
              p === 1
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :p@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Proc@0x1008)
          PatchPoint MethodRedefined(Proc@0x1008, ===@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact:Proc] = GuardType v10, ObjectSubclass[class_exact:Proc] recompile
          v26:BasicObject = InvokeProc v25, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_specialize_proc_call_splat() {
        eval("
            p = proc { }
            def test(p)
              empty = []
              p.call(*empty)
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :p@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v17:ArrayExact = NewArray
          v23:ArrayExact = ToArray v17
          v25:BasicObject = Send v12, :call, v23 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_dont_specialize_proc_call_kwarg() {
        eval("
            p = proc { |a:| a }
            def test(p)
              p.call(a: 1)
            end
            test p
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :p@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :p@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          v17:BasicObject = Send v10, :call, v15 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_dont_specialize_definedivar_with_immediate() {
        eval("
            module M
              def test = defined?(@a)
            end

            class Integer
              include M
            end

            1.test
            2.test
            TEST = M.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_definedivar_with_t_struct() {
        // Range is T_STRUCT (not T_OBJECT): falls back to DefinedIvar.
        eval("
            class C < Range
              def test = defined?(@a)
            end
            obj = C.new 0, 1
            obj.instance_variable_set(:@a, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_optimize_definedivar_polymorphic() {
        set_call_threshold(3);
        eval("
            class C
              def test = defined?(@a)
            end
            obj = C.new
            obj.instance_variable_set(:@a, 1)
            obj.test
            obj = C.new
            obj.instance_variable_set(:@b, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v10, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:NilClass = Const Value(nil)
          Jump bb4(v16)
        bb6():
          v18:CShape = LoadField v10, :shape_id@0x1000
          v19:CShape[0x1002] = Const CShape(0x1002)
          v20:CBool = IsBitEqual v18, v19
          CondBranch v20, bb7(), bb8()
        bb7():
          v22:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v22)
        bb8():
          v24:StringExact|NilClass = DefinedIvar v10, :@a
          Jump bb4(v24)
        bb4(v11:StringExact|NilClass):
          CheckInterrupts
          Return v11
        ");
    }

    // Two consecutive polymorphic `defined?` on the same `self` must both get
    // inline shape branches. Specializing the first rewrites `self` to a GuardType
    // wrapper, so `polymorphic_summary` must peel it (`chase_insn`, not `find_const`)
    // to match the profile entry; otherwise the second falls back to a generic DefinedIvar.
    #[test]
    fn test_optimize_two_consecutive_definedivar_polymorphic() {
        set_call_threshold(3);
        eval("
            class C
              def test = [defined?(@a), defined?(@b)]
            end
            obj = C.new
            obj.instance_variable_set(:@a, 1)
            obj.instance_variable_set(:@b, 1)
            obj.test
            obj = C.new
            obj.instance_variable_set(:@x, 1)
            obj.instance_variable_set(:@a, 1)
            obj.instance_variable_set(:@b, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @r"
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v10, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v16)
        bb6():
          v18:CShape = LoadField v10, :shape_id@0x1000
          v19:CShape[0x1010] = Const CShape(0x1010)
          v20:CBool = IsBitEqual v18, v19
          CondBranch v20, bb7(), bb8()
        bb7():
          v22:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v22)
        bb8():
          v24:StringExact|NilClass = DefinedIvar v10, :@a
          Jump bb4(v24)
        bb4(v11:StringExact|NilClass):
          v29:CShape = LoadField v10, :shape_id@0x1000
          v30:CShape[0x1001] = Const CShape(0x1001)
          v31:CBool = IsBitEqual v29, v30
          CondBranch v31, bb10(), bb11()
        bb10():
          v33:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb9(v33)
        bb11():
          v35:CShape = LoadField v10, :shape_id@0x1000
          v36:CShape[0x1010] = Const CShape(0x1010)
          v37:CBool = IsBitEqual v35, v36
          CondBranch v37, bb12(), bb13()
        bb12():
          v39:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb9(v39)
        bb13():
          v41:StringExact|NilClass = DefinedIvar v10, :@b
          Jump bb9(v41)
        bb9(v28:StringExact|NilClass):
          v44:ArrayExact = NewArray v11, v28
          CheckInterrupts
          Return v44
        ");
    }

    #[test]
    fn test_optimize_definedivar_polymorphic_with_immediate() {
        set_call_threshold(3);
        eval(r#"
            module M
              def test = defined?(@a)
            end

            class C
              include M
            end

            class Integer
              include M
            end

            obj = C.new
            obj.instance_variable_set(:@a, 1)

            obj.test
            1.test
            TEST = M.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v10, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v16)
        bb6():
          v18:StringExact|NilClass = DefinedIvar v10, :@a
          Jump bb4(v18)
        bb4(v11:StringExact|NilClass):
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_definedivar_polymorphic_with_t_struct() {
        set_call_threshold(3);
        eval(r#"
            module M
              def test = defined?(@a)
            end

            class C
              include M
            end

            class D < Range
              include M
            end

            obj = C.new
            obj.instance_variable_set(:@a, 1)

            range = D.new 0, 1
            range.instance_variable_set(:@a, 1)

            obj.test
            range.test
            TEST = M.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v10, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v16)
        bb6():
          v18:StringExact|NilClass = DefinedIvar v10, :@a
          Jump bb4(v18)
        bb4(v11:StringExact|NilClass):
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_definedivar_polymorphic_with_complex_shape() {
        set_call_threshold(3);
        eval(r#"
            module M
              def test = defined?(@a)
            end

            class C
              include M
            end

            class D
              include M
            end

            obj = C.new
            obj.instance_variable_set(:@a, 1)

            complex = D.new
            (0..1000).each do |i|
              complex.instance_variable_set(:"@v#{i}", i)
            end
            (0..1000).each do |i|
              complex.remove_instance_variable(:"@v#{i}")
            end

            obj.test
            complex.test
            TEST = M.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v10, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v16)
        bb6():
          v18:StringExact|NilClass = DefinedIvar v10, :@a
          Jump bb4(v18)
        bb4(v11:StringExact|NilClass):
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_dont_specialize_complex_shape_definedivar() {
        eval(r#"
            class C
              def test = defined?(@a)
            end
            obj = C.new
            (0..1000).each do |i|
              obj.instance_variable_set(:"@v#{i}", i)
            end
            (0..1000).each do |i|
              obj.remove_instance_variable(:"@v#{i}")
            end
            obj.test
            TEST = C.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_specialize_monomorphic_setivar_already_in_shape() {
        eval("
            @foo = 4
            def test = @foo = 5
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v14:HeapBasicObject = GuardType v6, HeapBasicObject
          v15:CShape = LoadField v14, :shape_id@0x1000
          v16:CShape[0x1001] = GuardBitEquals v15, CShape(0x1001) recompile
          StoreField v14, :@foo@0x1002, v10
          WriteBarrier v14, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_specialize_monomorphic_setivar_with_shape_transition() {
        eval("
            def test = @foo = 5
            test
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v14:HeapBasicObject = GuardType v6, HeapBasicObject
          v15:CShape = LoadField v14, :shape_id@0x1000
          v16:CShape[0x1001] = GuardBitEquals v15, CShape(0x1001) recompile
          StoreField v14, :@foo@0x1002, v10
          WriteBarrier v14, v10
          v19:CShape[0x1003] = Const CShape(0x1003)
          StoreField v14, :shape_id@0x1000, v19
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_specialize_multiple_monomorphic_setivar_with_shape_transition() {
        eval(r#"
            klass = Class.new do
              def test
                @foo = 1
                @bar = 2
              end
            end

            # Grow class max_iv_count so fresh instances can keep both writes
            # on the embedded fast path.
            warm = klass.new
            warm.instance_variable_set(:@warm1, 1)
            warm.instance_variable_set(:@warm2, 2)

            obj = klass.new
            obj.test
            TEST = klass.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          v13:HeapBasicObject = GuardType v6, HeapBasicObject
          v14:CShape = LoadField v13, :shape_id@0x1000
          v15:CShape[0x1001] = GuardBitEquals v14, CShape(0x1001) recompile
          StoreField v13, :@foo@0x1002, v10
          WriteBarrier v13, v10
          v18:CShape[0x1003] = Const CShape(0x1003)
          StoreField v13, :shape_id@0x1000, v18
          v23:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          StoreField v13, :@bar@0x1004, v23
          WriteBarrier v13, v23
          v32:CShape[0x1005] = Const CShape(0x1005)
          StoreField v13, :shape_id@0x1000, v32
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_specialize_setivar_with_t_data() {
        eval("
            class C < Range
              def test = @a = 5
            end
            obj = C.new 0, 1
            obj.instance_variable_set(:@a, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          SetIvar v6, :@a, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_polymorphic_setivar() {
        set_call_threshold(3);
        eval("
            class C
              def test = @a = 5
            end
            obj = C.new
            obj.instance_variable_set(:@a, 1)
            obj.test
            obj = C.new
            obj.instance_variable_set(:@b, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          SetIvar v6, :@a, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_complex_shape_setivar() {
        eval(r#"
            class C
              def test = @a = 5
            end
            obj = C.new
            (0..1000).each do |i|
              obj.instance_variable_set(:"@v#{i}", i)
            end
            (0..1000).each do |i|
              obj.remove_instance_variable(:"@v#{i}")
            end
            obj.test
            TEST = C.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          SetIvar v6, :@a, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_setivar_when_next_shape_is_complex() {
        eval(r#"
            class AboutToBeTooComplex
              def test = @abc = 5
            end
            SHAPE_MAX_VARIATIONS = 8  # see shape.h
            SHAPE_MAX_VARIATIONS.times do
              AboutToBeTooComplex.new.instance_variable_set(:"@a#{_1}", 1)
            end
            AboutToBeTooComplex.new.test
            TEST = AboutToBeTooComplex.instance_method(:test)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          SetIvar v6, :@abc, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_elide_freeze_with_frozen_hash() {
        eval("
            def test = {}.freeze
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
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_dont_optimize_hash_freeze_if_redefined() {
        eval("
            class Hash
              def freeze; end
            end
            def test = {}.freeze
        ");
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
    fn test_elide_freeze_with_refrozen_hash() {
        eval("
            def test = {}.freeze.freeze
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
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_hash() {
        eval("
            def test = {}.dup.freeze
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
          v10:HashExact = NewHash
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, dup@0x1008, cme:0x1010)
          v23:BasicObject = CCallWithFrame v10, :Kernel#dup@0x1038
          v14:BasicObject = Send v23, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_no_elide_freeze_hash_with_args() {
        eval("
            def test = {}.freeze(nil)
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
          v10:HashExact = NewHash
          v12:NilClass = Const Value(nil)
          v14:BasicObject = Send v10, :freeze, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_elide_freeze_with_frozen_ary() {
        eval("
            def test = [].freeze
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
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_elide_freeze_with_refrozen_ary() {
        eval("
            def test = [].freeze.freeze
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
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_ary() {
        eval("
            def test = [].dup.freeze
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, dup@0x1008, cme:0x1010)
          v23:BasicObject = CCallWithFrame v10, :Kernel#dup@0x1038
          v14:BasicObject = Send v23, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_no_elide_freeze_ary_with_args() {
        eval("
            def test = [].freeze(nil)
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
          v10:ArrayExact = NewArray
          v12:NilClass = Const Value(nil)
          v14:BasicObject = Send v10, :freeze, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_elide_freeze_with_frozen_str() {
        eval("
            def test = ''.freeze
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_elide_freeze_with_refrozen_str() {
        eval("
            def test = ''.freeze.freeze
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_str() {
        eval("
            def test = ''.dup.freeze
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          v24:BasicObject = CCallWithFrame v11, :String#dup@0x1040
          v15:BasicObject = Send v24, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_no_elide_freeze_str_with_args() {
        eval("
            def test = ''.freeze(nil)
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          v13:NilClass = Const Value(nil)
          v15:BasicObject = Send v11, :freeze, v13 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_elide_uminus_with_frozen_str() {
        eval("
            def test = -''
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_elide_uminus_with_refrozen_str() {
        eval("
            def test = -''.freeze
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_no_elide_uminus_with_unfrozen_str() {
        eval("
            def test = -''.dup
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          v24:BasicObject = CCallWithFrame v11, :String#dup@0x1040
          v15:BasicObject = Send v24, :-@ # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_objtostring_anytostring_string() {
        eval(r##"
            def test = "#{('foo')}"
        "##);
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
          v13:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:StringExact = StringCopy v13
          v28:StringExact = StringConcat v10, v14
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_objtostring_anytostring_with_non_string() {
        eval(r##"
            def test = "#{1}"
        "##);
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
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v34:StringExact = CCallVariadic v12, :Integer#to_s@0x1040
          v26:StringExact = StringConcat v10, v34
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_optimize_objtostring_anytostring_recv_profiled() {
        eval("
            def test(a)
              \"#{a}\"
            end
            test('foo'); test('foo')
        ");

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
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          v19:String = GuardType v10, String
          v23:StringExact = StringConcat v14, v19
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_optimize_objtostring_anytostring_recv_profiled_string_subclass() {
        eval("
            class MyString < String; end

            def test(a)
              \"#{a}\"
            end
            foo = MyString.new('foo')
            test(MyString.new(foo)); test(MyString.new(foo))
        ");

        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
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
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(MyString@0x1010)
          v19:String = GuardType v10, String
          v23:StringExact = StringConcat v14, v19
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_optimize_objtostring_profiled_nonstring_falls_back_to_send() {
        eval("
            def test(a)
              \"#{a}\"
            end
            test([1,2,3]); test([1,2,3]) # No fast path for array
        ");

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
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v18:ArrayExact = GuardType v10, ArrayExact
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, to_s@0x1018, cme:0x1020)
          v33:BasicObject = CCallWithFrame v18, :Array#to_s@0x1048
          v21:String = AnyToString v18, str: v33
          v23:StringExact = StringConcat v14, v21
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_branchnil_nil() {
        eval("
            def test
              x = nil
              x&.itself
            end
        ");

        assert_snapshot!(hir_string("test"), @"
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
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          v21:NilClass = Const Value(nil)
          Return v21
        ");
    }

    #[test]
    fn test_branchnil_truthy() {
        eval("
            def test
              x = 1
              x&.itself
            end
        ");

        assert_snapshot!(hir_string("test"), @"
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
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          Return v13
        ");
    }

    #[test]
    fn test_dont_eliminate_load_from_non_frozen_array() {
        eval(r##"
            S = [4,5,6]
            def test = S[0]
            test
        "##);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, S)
          v12:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, []@0x1018, cme:0x1020)
          v34:CInt64[0] = Const CInt64(0)
          v28:CInt64 = ArrayLength v12
          v29:CInt64[0] = GuardLess v34, v28
          v33:BasicObject = ArrayAref v12, v29
          CheckInterrupts
          Return v33
        ");
       // TODO(max): Check the result of `S[0] = 5; test` using `inspect` to make sure that we
       // actually do the load at run-time.
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_in_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[1]
        "##);
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
          v13:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v34:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative() {
        eval(r##"
            def test = [4,5,6].freeze[-3]
        "##);
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
          v13:Fixnum[-3] = Const Value(-3)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v32:CInt64[-3] = Const CInt64(-3)
          v33:CInt64[3] = Const CInt64(3)
          v28:CInt64 = AdjustBounds v32, v33
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64 = GuardGreaterEq v28, v29
          v31:BasicObject = ArrayAref v11, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[-10]
        "##);
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
          v13:Fixnum[-10] = Const Value(-10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v32:CInt64[-10] = Const CInt64(-10)
          v33:CInt64[3] = Const CInt64(3)
          v28:CInt64 = AdjustBounds v32, v33
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64 = GuardGreaterEq v28, v29
          v31:BasicObject = ArrayAref v11, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[10]
        "##);
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
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          SideExit GuardLess
        ");
    }

    #[test]
    fn test_dont_optimize_array_aref_if_redefined() {
        eval(r##"
            class Array
              def [](index) = []
            end
            def test = [4,5,6].freeze[10]
        "##);
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
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PushInlineFrame v11 (0x1040), v13
          v30:ArrayExact = NewArray
          CheckInterrupts
          PopInlineFrame
          Return v30
        ");
    }

    #[test]
    fn test_dont_optimize_array_aset_if_redefined() {
        eval(r##"
            class Array
              def []=(*args); :redefined; end
            end

            def test(arr)
              arr[1] = 10
            end
        "##);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[10] = Const Value(10)
          SideExit NoProfileSend recompile
        ");
    }

    #[test]
    fn test_dont_optimize_array_max_if_redefined() {
        eval(r##"
            class Array
              def max = []
            end
            def test = [4,5,6].max
        "##);
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
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:ArrayExact = ArrayDup v10
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, max@0x1010, cme:0x1018)
          PushInlineFrame v11 (0x1040)
          v26:ArrayExact = NewArray
          CheckInterrupts
          PopInlineFrame
          Return v26
        ");
    }

    #[test]
    fn test_set_type_from_constant() {
        eval("
            MY_SET = Set.new

            def test = MY_SET

            test
            test
        ");
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, MY_SET)
          v12:SetExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_regexp_type() {
        eval("
            def test = /a/
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
          v10:RegexpExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_bmethod_send_direct() {
        eval("
            define_method(:zero) { :b }
            define_method(:one) { |arg| arg }

            def test = one(zero)
            test
        ");
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
          PatchPoint SingleRactorMode
          PatchPoint MethodRedefined(Object@0x1000, zero@0x1008, cme:0x1010)
          v22:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v23:StaticSymbol[:b] = Const Value(VALUE(0x1038))
          PatchPoint MethodRedefined(Object@0x1000, one@0x1040, cme:0x1048)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_symbol_block_bmethod() {
        eval("
            define_method(:identity, &:itself)
            def test = identity(100)
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[100] = Const Value(100)
          v13:BasicObject = Send v6, :identity, v11 # SendFallbackReason: Bmethod: Proc object is not defined by an ISEQ
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_call_bmethod_with_block() {
        eval("
            define_method(:bmethod) { :b }
            def test = (bmethod {})
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:BasicObject = Send v6, 0x1000, :bmethod # SendFallbackReason: Send: unsupported method type Bmethod
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_call_shareable_bmethod() {
        eval("
            class Foo
              class << self
                define_method(:identity, &(Ractor.make_shareable ->(val){val}))
              end
            end
            def test = Foo.identity(100)
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
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
          PatchPoint StableConstantNames(0x1000, Foo)
          v12:ClassSubclass[Foo@0x1008] = Const Value(VALUE(0x1008))
          v14:Fixnum[100] = Const Value(100)
          PatchPoint MethodRedefined(Class@0x1010, identity@0x1018, cme:0x1020)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_nil_nil_specialized_to_ccall() {
        eval("
            def test = nil.nil?
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
          v10:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v21:TrueClass = Const Value(true)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_eliminate_nil_nil_specialized_to_ccall() {
        eval("
            def test
              nil.nil?
              1
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v17:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_non_nil_nil_specialized_to_ccall() {
        eval("
            def test = 1.nil?
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v21:FalseClass = Const Value(false)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_eliminate_non_nil_nil_specialized_to_ccall() {
        eval("
            def test
              1.nil?
              2
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v17:Fixnum[2] = Const Value(2)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_guard_nil_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(nil)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(NilClass@0x1008, nil?@0x1010, cme:0x1018)
          v24:NilClass = GuardType v10, NilClass recompile
          v25:TrueClass = Const Value(true)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_false_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(false)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(FalseClass@0x1008, nil?@0x1010, cme:0x1018)
          v24:FalseClass = GuardType v10, FalseClass recompile
          v25:FalseClass = Const Value(false)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_true_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(true)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(TrueClass@0x1008, nil?@0x1010, cme:0x1018)
          v24:TrueClass = GuardType v10, TrueClass recompile
          v25:FalseClass = Const Value(false)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_symbol_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(:foo)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Symbol@0x1008, nil?@0x1010, cme:0x1018)
          v24:StaticSymbol = GuardType v10, StaticSymbol recompile
          v25:FalseClass = Const Value(false)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_fixnum_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1008, nil?@0x1010, cme:0x1018)
          v24:Fixnum = GuardType v10, Fixnum recompile
          v25:FalseClass = Const Value(false)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_float_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(1.0)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Float@0x1008, nil?@0x1010, cme:0x1018)
          v24:Flonum = GuardType v10, Flonum recompile
          v25:FalseClass = Const Value(false)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_guard_string_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test('foo')
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, nil?@0x1010, cme:0x1018)
          v25:StringExact = GuardType v10, StringExact recompile
          v26:FalseClass = Const Value(false)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_truthy() {
        eval("
            def test(a) = !a

            test([])
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
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, !@0x1010, cme:0x1018)
          v25:ArrayExact = GuardType v10, ArrayExact recompile
          v26:FalseClass = Const Value(false)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_false() {
        eval("
            def test(a) = !a

            test(false)
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
          PatchPoint MethodRedefined(FalseClass@0x1008, !@0x1010, cme:0x1018)
          v24:FalseClass = GuardType v10, FalseClass recompile
          v25:TrueClass = Const Value(true)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_nil() {
        eval("
            def test(a) = !a

            test(nil)
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
          PatchPoint MethodRedefined(NilClass@0x1008, !@0x1010, cme:0x1018)
          v24:NilClass = GuardType v10, NilClass recompile
          v25:TrueClass = Const Value(true)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_falsy() {
        eval("
            def test(a) = !(if a then false else nil end)

            # TODO(max): Make this not GuardType NilClass and instead just reason
            # statically
            test(false)
            test(true)
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
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          CondBranch v16, bb6(), bb4(v9, v17)
        bb6():
          v19:Truthy = RefineType v10, Truthy
          v21:FalseClass = Const Value(false)
          CheckInterrupts
          Jump bb5(v9, v19, v21)
        bb4(v25:BasicObject, v26:Falsy):
          v29:NilClass = Const Value(nil)
          Jump bb5(v25, v26, v29)
        bb5(v31:BasicObject, v32:BasicObject, v33:Falsy):
          v38:CBool = HasType v33, FalseClass
          CondBranch v38, bb8(), bb9()
        bb8():
          PatchPoint MethodRedefined(FalseClass@0x1008, !@0x1010, cme:0x1018)
          v59:TrueClass = Const Value(true)
          Jump bb7(v59)
        bb9():
          v44:CBool = HasType v33, NilClass
          CondBranch v44, bb10(), bb11()
        bb10():
          PatchPoint MethodRedefined(NilClass@0x1040, !@0x1010, cme:0x1018)
          v62:TrueClass = Const Value(true)
          Jump bb7(v62)
        bb11():
          v50:BasicObject = Send v33, :! # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb7(v50)
        bb7(v37:BasicObject):
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_specialize_array_empty_p() {
        eval("
            def test(a) = a.empty?

            test([])
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
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, empty?@0x1010, cme:0x1018)
          v25:ArrayExact = GuardType v10, ArrayExact recompile
          v26:CInt64 = ArrayLength v25
          v27:CInt64[0] = Const CInt64(0)
          v28:CBool = IsBitEqual v26, v27
          v29:BoolExact = BoxBool v28
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_specialize_hash_empty_p_to_ccall() {
        eval("
            def test(a) = a.empty?

            test({})
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
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, empty?@0x1010, cme:0x1018)
          v25:HashExact = GuardType v10, HashExact recompile
          v26:BoolExact = CCall v25, :Hash#empty?@0x1040
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_basic_object_eq_to_ccall() {
        eval("
            class C; end
            def test(a, b) = a == b

            test(C.new, C.new)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, ==@0x1010, cme:0x1018)
          v29:ObjectSubclass[class_exact:C] = GuardType v12, ObjectSubclass[class_exact:C] recompile
          v30:CBool = IsBitEqual v29, v13
          v31:BoolExact = BoxBool v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_guard_fixnum_and_fixnum() {
        eval("
            def test(x, y) = x & y

            test(1, 2)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, &@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAnd v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_guard_fixnum_or_fixnum() {
        eval("
            def test(x, y) = x | y

            test(1, 2)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, |@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumOr v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_method_redefinition_patch_point_on_top_level_method() {
        eval("
            def foo; end
            def test = foo

            test; test
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:NilClass = Const Value(nil)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_optimize_getivar_embedded() {
        eval("
            class C
              attr_reader :foo
              def initialize
                @foo = 42
              end
            end

            O = C.new
            def test(o) = o.foo
            test O
            test O
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v25:CShape = LoadField v23, :shape_id@0x1040
          v26:CShape[0x1041] = GuardBitEquals v25, CShape(0x1041) recompile
          v27:BasicObject = LoadField v23, :@foo@0x1042
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_getivar_complex() {
        eval(r#"
            class C
              attr_reader :foo
              def initialize
                1000.times do |i|
                  instance_variable_set("@v#{i}", i)
                end
                @foo = 42
              end
            end

            O = C.new
            def test(o) = o.foo
            test O
            test O
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:13:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v24:BasicObject = GetIvar v23, :@foo
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_getivar_shape_guard_recompile() {
        // Call with one shape to compile, then call with a different shape to
        // trigger shape guard exits and recompilation. On the recompiled version,
        // GetIvar stays as a C call because iseq_to_hir handles polymorphic
        // branching at parse time for getinstancevariable.
        eval("
            class C
              def initialize(extra = false)
                @bar = 0 if extra  # changes the shape
                @foo = 42
              end
              def foo = @foo
            end

            c = C.new
            c.foo  # profile
            c.foo  # compile (version 1 with shape guard)
            d = C.new(true)  # same class, different shape
            100.times { d.foo }  # trigger shape guard exits -> recompile
            100.times { c.foo }  # run recompiled version (version 2)
        ");
        // After recompilation, iseq_to_hir generates polymorphic branches at
        // parse time using the exit-profiled shapes: two optimized LoadField
        // fast paths plus a GetIvar C call fallback.
        assert_snapshot!(hir_string_proc("C.new.method(:foo)"), @"
        fn foo@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:HeapBasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:HeapBasicObject):
          PatchPoint SingleRactorMode
          v13:CShape = LoadField v6, :shape_id@0x1000
          v14:CShape[0x1001] = Const CShape(0x1001)
          v15:CBool = IsBitEqual v13, v14
          CondBranch v15, bb5(), bb6()
        bb5():
          v17:BasicObject = LoadField v6, :@foo@0x1002
          Jump bb4(v17)
        bb6():
          v19:CShape = LoadField v6, :shape_id@0x1000
          v20:CShape[0x1003] = Const CShape(0x1003)
          v21:CBool = IsBitEqual v19, v20
          CondBranch v21, bb7(), bb8()
        bb7():
          v23:BasicObject = LoadField v6, :@foo@0x1004
          Jump bb4(v23)
        bb8():
          v25:BasicObject = GetIvar v6, :@foo
          Jump bb4(v25)
        bb4(v12:BasicObject):
          CheckInterrupts
          Return v12
        ");
    }

    // The following tests pin down the soundness boundary of the `self:
    // HeapBasicObject` inference (see `iseq_self_is_heap_object`). A `def` method
    // gets `self: HeapBasicObject` only when its owning class can never produce an
    // immediate receiver. For each class below, `self` must stay `BasicObject`:
    // the six immediate classes have no default allocator, and Object/BasicObject/
    // Numeric use the default allocator but are ancestors of immediates (caught by
    // the Integer kind_of check). Each test reopens the class, compiles the method
    // (call threshold is 30), then checks the resulting `self` type.

    #[test]
    fn test_self_not_heap_object_owner_integer() {
        eval("
            class Integer
              def probe = @foo
            end
            100.times { 5.probe }
        ");
        assert_snapshot!(hir_string_proc("5.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_symbol() {
        eval("
            class Symbol
              def probe = @foo
            end
            100.times { :sym.probe }
        ");
        assert_snapshot!(hir_string_proc(":sym.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_float() {
        eval("
            class Float
              def probe = @foo
            end
            100.times { 1.5.probe }
        ");
        assert_snapshot!(hir_string_proc("1.5.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_nil_class() {
        eval("
            class NilClass
              def probe = @foo
            end
            100.times { nil.probe }
        ");
        assert_snapshot!(hir_string_proc("nil.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_true_class() {
        eval("
            class TrueClass
              def probe = @foo
            end
            100.times { true.probe }
        ");
        assert_snapshot!(hir_string_proc("true.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_false_class() {
        eval("
            class FalseClass
              def probe = @foo
            end
            100.times { false.probe }
        ");
        assert_snapshot!(hir_string_proc("false.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_self_not_heap_object_owner_object() {
        // Object uses the default allocator, but Integer (and every other immediate)
        // descends from it, so a method on Object can run with an immediate self.
        eval("
            class Object
              def probe = @foo
            end
            o = Object.new
            100.times { o.probe }
        ");
        assert_snapshot!(hir_string_proc("Object.new.method(:probe)"), @"
        fn probe@<compiled>:3:
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
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:NilClass = Const Value(nil)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_self_not_heap_object_owner_basic_object() {
        // Same as Object: BasicObject has the default allocator but is the root of
        // the immediate classes' ancestry.
        eval("
            class BasicObject
              def probe = @foo
            end
            o = Object.new
            100.times { o.probe }
        ");
        assert_snapshot!(hir_string_proc("Object.new.method(:probe)"), @"
        fn probe@<compiled>:3:
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
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:NilClass = Const Value(nil)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_self_not_heap_object_owner_numeric() {
        // Numeric has the default allocator but Integer/Float descend from it, so a
        // method on Numeric can run with an immediate self.
        eval("
            class Numeric
              def probe = @foo
            end
            100.times { 5.probe }
        ");
        assert_snapshot!(hir_string_proc("5.method(:probe)"), @"
        fn probe@<compiled>:3:
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
    fn test_definedivar_shape_guard_recompile() {
        // Call with one shape to compile, then call with a different shape to
        // trigger shape guard exits and recompilation. On the recompiled version,
        // DefinedIvar uses polymorphic fast paths plus a C call fallback.
        eval("
            class C
              def initialize(extra = false)
                @bar = 0 if extra  # changes the shape
                @foo = 42
              end
              def has_foo = defined?(@foo)
            end

            c = C.new
            c.has_foo  # profile
            c.has_foo  # compile (version 1 with shape guard)
            d = C.new(true)  # same class, different shape
            100.times { d.has_foo }  # trigger shape guard exits -> recompile
            100.times { c.has_foo }  # run recompiled version (version 2)
        ");
        assert_snapshot!(hir_string_proc("C.new.method(:has_foo)"), @"
        fn has_foo@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:HeapBasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:HeapBasicObject):
          v12:CShape = LoadField v6, :shape_id@0x1000
          v13:CShape[0x1001] = Const CShape(0x1001)
          v14:CBool = IsBitEqual v12, v13
          CondBranch v14, bb5(), bb6()
        bb5():
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v16)
        bb6():
          v18:CShape = LoadField v6, :shape_id@0x1000
          v19:CShape[0x1010] = Const CShape(0x1010)
          v20:CBool = IsBitEqual v18, v19
          CondBranch v20, bb7(), bb8()
        bb7():
          v22:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          Jump bb4(v22)
        bb8():
          v24:StringExact|NilClass = DefinedIvar v6, :@foo
          Jump bb4(v24)
        bb4(v11:StringExact|NilClass):
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_setivar_shape_guard_recompile() {
        // Call with one shape to compile, then call with a different shape to
        // trigger shape guard exits and recompilation. On the recompiled version,
        // SetIvar stays as a C call fallback to avoid more shape guard exits.
        eval("
            class C
              def initialize(extra = false)
                @bar = 0 if extra  # changes the shape
                @foo = 42
              end
              def foo = @foo = 5
            end

            c = C.new
            c.foo  # profile
            c.foo  # compile (version 1 with shape guard)
            d = C.new(true)  # same class, different shape
            100.times { d.foo }  # trigger shape guard exits -> recompile
            100.times { c.foo }  # run recompiled version (version 2)
        ");
        assert_snapshot!(hir_string_proc("C.new.method(:foo)"), @"
        fn foo@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:HeapBasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:HeapBasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          SetIvar v6, :@foo, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_setivar_shape_guard_attr_writer_no_recompile() {
        // attr_writer SetIvar has no inline cache and may target a receiver
        // operand other than CFP self, so don't recompile here yet.
        eval("
            class C
              attr_writer :foo
              def initialize(extra = false)
                @bar = 0 if extra  # changes the shape
                @foo = 42
              end
            end

            class D
              def write(obj)
                obj.foo = 5
              end
            end

            c = C.new
            d = D.new
            d.write(c)  # profile
            d.write(c)  # compile (version 1 with shape guard)
            e = C.new(true)  # same class, different shape
            100.times { d.write(e) }  # shape guard exits, but no recompile
        ");
        assert_snapshot!(hir_string_proc("D.new.method(:write)"), @"
        fn write@<compiled>:12:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :obj@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:HeapBasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :obj@1
          Jump bb3(v6, v7)
        bb3(v9:HeapBasicObject, v10:BasicObject):
          v17:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1008, foo=@0x1010, cme:0x1018)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v30:CShape = LoadField v28, :shape_id@0x1040
          v31:CShape[0x1041] = GuardBitEquals v30, CShape(0x1041)
          StoreField v28, :@foo@0x1042, v17
          WriteBarrier v28, v17
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_optimize_getivar_on_module_embedded() {
        eval("
            module M
              @foo = 42
              def self.test = @foo
            end
            M.test
        ");
        assert_snapshot!(hir_string_proc("M.method(:test)"), @"
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
          PatchPoint SingleRactorMode
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:RubyValue = LoadField v11, :fields_obj@0x1002
          v15:BasicObject = LoadField v14, :@foo@0x1003
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_optimize_getivar_on_module_complex() {
        eval(r#"
            module M
              @foo = 42
              for i in 0...1000
                instance_variable_set("@v#{i}", i)
              end
              def self.test = @foo
            end
            M.test
        "#);
        assert_snapshot!(hir_string_proc("M.method(:test)"), @"
        fn test@<compiled>:7:
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
    fn test_no_side_exit_assertion() {
        eval("
          def side_exit = ::RubyVM::ZJIT.induce_side_exit!
          side_exit
        ");
        std::panic::catch_unwind(|| assert_compiles("side_exit")).expect_err("Should panic because the program should side exit");
    }

    #[test]
    fn test_optimize_getivar_on_class_embedded() {
        eval("
            class C
              @foo = 42
              def self.test = @foo
            end
            C.test
        ");
        assert_snapshot!(assert_compiles("C.test"), @"42");
        assert_snapshot!(hir_string_proc("C.method(:test)"), @"
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
          PatchPoint SingleRactorMode
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:RubyValue = LoadField v11, :fields_obj@0x1002
          v15:BasicObject = LoadField v14, :@foo@0x1003
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_optimize_getivar_on_class_complex() {
        eval(r#"
            class C
              @foo = 42
              for i in 0...1000
                instance_variable_set("@v#{i}", i)
              end
              def self.test = @foo
            end
            C.test
        "#);
        assert_snapshot!(hir_string_proc("C.method(:test)"), @"
        fn test@<compiled>:7:
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
    fn test_optimize_getivar_on_t_struct() {
        // Range is T_STRUCT (not T_DATA): falls back to CCall
        eval("
            class C < Range
              def test = @a
            end
            obj = C.new 0, 1
            obj.instance_variable_set(:@a, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          PatchPoint SingleRactorMode
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:CAttrIndex[0] = Const CAttrIndex(0)
          v15:BasicObject = CCall v11, :rb_ivar_get_at_no_ractor_check@0x1008, v14
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_optimize_getivar_on_t_data() {
        // T_DATA uses fields_obj for instance variables.
        eval("
            class C < Thread
              def test = @a
            end
            obj = C.new { }
            obj.join
            obj.instance_variable_set(:@a, 1)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          PatchPoint SingleRactorMode
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v12:CShape = LoadField v11, :shape_id@0x1000
          v13:CShape[0x1001] = GuardBitEquals v12, CShape(0x1001) recompile
          v14:RubyValue = LoadField v11, :fields_obj@0x1002
          v15:BasicObject = LoadField v14, :@a@0x1002
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_optimize_getivar_on_t_data_complex_fields() {
        // T_DATA with enough ivars to force heap field storage
        eval("
            class C < Thread
              def test = @var1000
            end
            obj = C.new { }
            obj.join
            1000.times { |i| obj.instance_variable_set(:\"@var#{i}\", 1) }
            obj.instance_variable_set(:@var1000, 42)
            obj.test
            TEST = C.instance_method(:test)
        ");
        assert_snapshot!(hir_string_proc("TEST"), @"
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
          PatchPoint SingleRactorMode
          v11:BasicObject = GetIvar v6, :@var1000
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_getivar_on_module_multi_ractor() {
        eval("
            module M
              @foo = 42
              def self.test = @foo
            end
            Ractor.new {}.value
            M.test
        ");
        assert_snapshot!(hir_string_proc("M.method(:test)"), @"
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
          SideExit UnhandledYARVInsn(getinstancevariable)
        ");
    }

    #[test]
    fn test_optimize_attr_reader_on_module_multi_ractor() {
        eval("
            module M
              @foo = 42
              class << self
                attr_reader :foo
              end
              def self.test = foo
            end
            Ractor.new {}.value
            M.test
        ");
        assert_snapshot!(hir_string_proc("M.method(:test)"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:BasicObject = Send v6, :foo # SendFallbackReason: Single-ractor mode required
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_getivar_polymorphic() {
        set_call_threshold(3);
        eval(r#"
            class C
              def foo_then_many
                @foo = 1
                10.times { |i| instance_variable_set(:"@v#{i}", i) }
                @bar = 2
              end

              def many_then_foo
                10.times { |i| instance_variable_set(:"@v#{i}", i) }
                @bar = 3
                @foo = 4
              end

              def foo = @foo + 1
            end

            O1 = C.new
            O1.foo_then_many
            O2 = C.new
            O2.many_then_foo
            O1.foo
            O2.foo
        "#);
        assert_snapshot!(hir_string_proc("C.instance_method(:foo)"), @"
        fn foo@<compiled>:15:
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
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v13:CShape = LoadField v11, :shape_id@0x1000
          v14:CShape[0x1001] = Const CShape(0x1001)
          v15:CBool = IsBitEqual v13, v14
          CondBranch v15, bb5(), bb6()
        bb5():
          v17:BasicObject = LoadField v11, :@foo@0x1002
          Jump bb4(v17)
        bb6():
          v19:CShape = LoadField v11, :shape_id@0x1000
          v20:CShape[0x1003] = Const CShape(0x1003)
          v21:CBool = IsBitEqual v19, v20
          CondBranch v21, bb7(), bb8()
        bb7():
          v23:CPtr = LoadField v11, :as_heap@0x1004
          v24:BasicObject = LoadField v23, :@foo@0x1005
          Jump bb4(v24)
        bb8():
          v26:BasicObject = GetIvar v11, :@foo
          Jump bb4(v26)
        bb4(v12:BasicObject):
          v29:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v40:Fixnum = GuardType v12, Fixnum recompile
          v41:Fixnum = FixnumAdd v40, v29
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_optimize_getivar_skewed_polymorphic() {
        // Use threshold=6 so we get 5 profile samples.
        // 4 calls with shape A, 1 with shape B = 80% skew (>= 75% threshold).
        set_call_threshold(6);
        eval(r#"
            class C
              def foo_then_many
                @foo = 1
                100.times { |i| instance_variable_set(:"@v#{i}", i) }
                @bar = 2
              end

              def many_then_foo
                100.times { |i| instance_variable_set(:"@v#{i}", i) }
                @bar = 3
                @foo = 4
              end

              def foo = @foo + 1
            end

            O1 = C.new
            O1.foo_then_many
            O2 = C.new
            O2.many_then_foo
            O1.foo
            O1.foo
            O1.foo
            O1.foo
            O2.foo
        "#);
        assert_snapshot!(hir_string_proc("C.instance_method(:foo)"), @"
        fn foo@<compiled>:15:
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
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v13:CShape = LoadField v11, :shape_id@0x1000
          v14:CShape[0x1001] = Const CShape(0x1001)
          v15:CBool = IsBitEqual v13, v14
          CondBranch v15, bb5(), bb6()
        bb5():
          v17:CPtr = LoadField v11, :as_heap@0x1002
          v18:BasicObject = LoadField v17, :@foo@0x1003
          Jump bb4(v18)
        bb6():
          v20:CShape = LoadField v11, :shape_id@0x1000
          v21:CShape[0x1004] = Const CShape(0x1004)
          v22:CBool = IsBitEqual v20, v21
          CondBranch v22, bb7(), bb8()
        bb7():
          v24:BasicObject = LoadField v11, :@foo@0x1005
          Jump bb4(v24)
        bb8():
          v26:BasicObject = GetIvar v11, :@foo
          Jump bb4(v26)
        bb4(v12:BasicObject):
          v29:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v40:Fixnum = GuardType v12, Fixnum recompile
          v41:Fixnum = FixnumAdd v40, v29
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_optimize_getivar_polymorphic_with_subclass() {
        set_call_threshold(3);
        eval(r#"
            class C
              def initialize
                @foo = 3
              end

              def foo = @foo + 1
            end

            class D < C
              def initialize
                super
                @bar = 4
              end
            end

            O1 = C.new
            O2 = D.new
            O1.foo
            O2.foo
        "#);
        assert_snapshot!(hir_string_proc("C.instance_method(:foo)"), @"
        fn foo@<compiled>:7:
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
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v13:CShape = LoadField v11, :shape_id@0x1000
          v14:CShape[0x1001] = Const CShape(0x1001)
          v15:CBool = IsBitEqual v13, v14
          CondBranch v15, bb5(), bb6()
        bb5():
          v17:BasicObject = LoadField v11, :@foo@0x1002
          Jump bb4(v17)
        bb6():
          v19:CShape = LoadField v11, :shape_id@0x1000
          v20:CShape[0x1003] = Const CShape(0x1003)
          v21:CBool = IsBitEqual v19, v20
          CondBranch v21, bb7(), bb8()
        bb7():
          v23:BasicObject = LoadField v11, :@foo@0x1002
          Jump bb4(v23)
        bb8():
          v25:BasicObject = GetIvar v11, :@foo
          Jump bb4(v25)
        bb4(v12:BasicObject):
          v28:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v39:Fixnum = GuardType v12, Fixnum recompile
          v40:Fixnum = FixnumAdd v39, v28
          CheckInterrupts
          Return v40
        ");
    }

    #[test]
    fn test_getivar_polymorphic_t_class_and_t_data() {
        set_call_threshold(3);
        eval(r#"
          module Reader
            def test = @a
          end

          class A
            extend Reader
            @a = 0
          end

          ARGF.instance_eval do
            extend Reader
            @a = :a
          end

          A.test
          ARGF.test
        "#);
        assert_snapshot!(assert_compiles("[A.test, ARGF.test]"), @"[0, :a]");
        assert_snapshot!(hir_string_proc("Reader.instance_method(:test)"), @"
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
          PatchPoint SingleRactorMode
          v11:HeapBasicObject = GuardType v6, HeapBasicObject
          v13:CShape = LoadField v11, :shape_id@0x1000
          v14:CShape[0x1001] = Const CShape(0x1001)
          v15:CBool = IsBitEqual v13, v14
          CondBranch v15, bb5(), bb6()
        bb5():
          v17:RubyValue = LoadField v11, :fields_obj@0x1002
          v18:BasicObject = LoadField v17, :@a@0x1002
          Jump bb4(v18)
        bb6():
          v20:CShape = LoadField v11, :shape_id@0x1000
          v21:CShape[0x1003] = Const CShape(0x1003)
          v22:CBool = IsBitEqual v20, v21
          CondBranch v22, bb7(), bb8()
        bb7():
          v24:RubyValue = LoadField v11, :fields_obj@0x1004
          v25:BasicObject = LoadField v24, :@a@0x1002
          Jump bb4(v25)
        bb8():
          v27:BasicObject = GetIvar v11, :@a
          Jump bb4(v27)
        bb4(v12:BasicObject):
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_dont_optimize_attr_accessor_polymorphic() {
        set_call_threshold(3);
        eval("
            class C
              attr_reader :foo, :bar

              def foo_then_bar
                @foo = 1
                @bar = 2
              end

              def bar_then_foo
                @bar = 3
                @foo = 4
              end
            end

            O1 = C.new
            O1.foo_then_bar
            O2 = C.new
            O2.bar_then_foo
            def test(o) = o.foo
            test O1
            test O2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:20:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:CBool = HasType v10, ObjectSubclass[class_exact:C]
          CondBranch v16, bb5(), bb6()
        bb5():
          v19:ObjectSubclass[class_exact:C] = RefineType v10, ObjectSubclass[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v31:BasicObject = GetIvar v19, :@foo
          Jump bb4(v31)
        bb6():
          v22:BasicObject = Send v10, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v22)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_dont_optimize_getivar_with_complex_shape() {
        eval(r#"
            class C
              attr_accessor :foo
            end
            obj = C.new
            (0..1000).each do |i|
              obj.instance_variable_set(:"@v#{i}", i)
            end
            (0..1000).each do |i|
              obj.remove_instance_variable(:"@v#{i}")
            end
            def test(o) = o.foo
            test obj
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:12:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v24:BasicObject = GetIvar v23, :@foo
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_send_with_block() {
        eval(r#"
            def test = [1, 2, 3].map { |x| x * 2 }
            test; test
        "#);
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
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:ArrayExact = ArrayDup v10
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, map@0x1010, cme:0x1018)
          v22:BasicObject = SendDirect v11, 0x1040, :map (0x1050)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_optimize_send_variadic_with_block() {
        eval(r#"
            A = [1, 2, 3]
            B = ["a", "b", "c"]

            def test
              result = []
              A.zip(B) { |x, y| result << [x, y] }
              result
            end

            test; test
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
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
          v13:ArrayExact = NewArray
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, A)
          v19:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, B)
          v23:ArrayExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          PatchPoint NoSingletonClass(Array@0x1020)
          PatchPoint MethodRedefined(Array@0x1020, zip@0x1028, cme:0x1030)
          v42:BasicObject = CCallVariadic v19, :Array#zip@0x1058, v23
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_do_not_optimize_send_with_block_forwarding() {
        eval(r#"
            def test(&block) = [].map(&block)
            test { |x| x }; test { |x| x }
        "#);
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
          v14:ArrayExact = NewArray
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v25:CInt64 = GuardAnyBitSet v24, CUInt64(1) recompile
          v26:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v26, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v29:BasicObject = Send v14, &block, :map, v16 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_replace_block_param_proxy_with_nil() {
        eval(r#"
            def test(&block) = [].map(&block)
            test; test
        "#);
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
          v14:ArrayExact = NewArray
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v25:CInt64[0] = GuardBitEquals v24, CInt64(0) recompile
          v26:NilClass = Const Value(nil)
          Jump bb6(v26, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v35:NilClass = GuardBitEquals v16, Value(nil) recompile
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, map@0x1010, cme:0x1018)
          v40:BasicObject = SendDirect v14, 0x1040, :map (0x1050)
          CheckInterrupts
          Return v40
        ");
    }

    #[test]
    fn test_replace_block_param_proxy_with_nil_nested() {
        eval(r#"
            def test(&block)
              proc do
                [].map(&block)
              end
            end
            test; test
        "#);
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
          v10:ArrayExact = NewArray
          v13:CPtr = GetEP 1
          v14:CUInt64 = LoadField v13, :VM_ENV_DATA_INDEX_FLAGS@0x1000
          v15:CBool = IsBlockParamModified v14
          CondBranch v15, bb4(), bb5()
        bb4():
          v17:BasicObject = LoadField v13, :block@0x1001
          Jump bb6(v17)
        bb5():
          v19:CInt64 = LoadField v13, :VM_ENV_DATA_INDEX_SPECVAL@0x1002
          v20:CInt64 = GuardAnyBitSet v19, CUInt64(1) recompile
          v21:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v21)
        bb6(v12:BasicObject):
          v24:BasicObject = Send v10, &block, :map, v12 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_send_iseq_with_block_no_callee_block_param() {
        let result = eval(r#"
            def foo
              yield 1
            end

            def test = foo { |x| x * 2 }
            test; test
        "#);
        assert_eq!(VALUE::fixnum_from_usize(2), result);
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
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          PushInlineFrame v18 (0x1038)
          v24:Fixnum[1] = Const Value(1)
          v26:BasicObject = InvokeBlock v24 # SendFallbackReason: InvokeBlock: not yet specialized
          CheckInterrupts
          PopInlineFrame
          Return v26
        ");
    }

    #[test]
    fn test_send_iseq_with_block_param_no_block() {
        set_max_versions(2);
        let result = eval("
            def foo(&blk)
              blk ? blk.call : 42
            end
            def test = foo
            test
            test
        ");
        assert_eq!(VALUE::fixnum_from_usize(42), result);
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
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v71:NilClass = Const Value(nil)
          PushInlineFrame v18 (0x1038)
          v27:CPtr = GetEP 0
          v28:CUInt64 = LoadField v27, :VM_ENV_DATA_INDEX_FLAGS@0x1040
          v29:CBool = IsBlockParamModified v28
          CondBranch v29, bb7(), bb8()
        bb7():
          v31:BasicObject = LoadField v27, :blk@0x1041
          Jump bb9(v31, v31)
        bb8():
          v33:CInt64 = LoadField v27, :VM_ENV_DATA_INDEX_SPECVAL@0x1042
          v34:CInt64[0] = GuardBitEquals v33, CInt64(0) recompile
          v35:NilClass = Const Value(nil)
          Jump bb9(v35, v71)
        bb9(v25:BasicObject, v26:BasicObject):
          CheckInterrupts
          v39:CBool = Test v25
          CondBranch v39, bb10(), bb6(v18, v26)
        bb10():
          v46:CPtr = GetEP 0
          v47:CUInt64 = LoadField v46, :VM_ENV_DATA_INDEX_FLAGS@0x1040
          v48:CBool = IsBlockParamModified v47
          CondBranch v48, bb11(), bb12()
        bb11():
          v50:BasicObject = LoadField v46, :blk@0x1041
          Jump bb13(v50, v50)
        bb12():
          v52:CInt64 = LoadField v46, :VM_ENV_DATA_INDEX_SPECVAL@0x1042
          v53:CInt64 = GuardAnyBitSet v52, CUInt64(1) recompile
          v54:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1048))
          Jump bb13(v54, v26)
        bb13(v44:BasicObject, v45:BasicObject):
          v57:BasicObject = Send v44, :call # SendFallbackReason: SendWithoutBlock: no profile data available
          CheckInterrupts
          Jump bb4(v57)
        bb6(v62:ObjectSubclass[class_exact*:Object@VALUE(0x1000)], v63:BasicObject):
          v66:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Jump bb4(v66)
        bb4(v72:BasicObject):
          PopInlineFrame
          CheckInterrupts
          Return v72
        ");
    }

    #[test]
    fn test_send_bmethod_with_block_param_no_block() {
        let result = eval("
            define_method(:foo) { |&blk|
              blk ? blk.call : 42
            }
            def test = foo
            test
            test
        ");
        assert_eq!(VALUE::fixnum_from_usize(42), result);
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
          PatchPoint SingleRactorMode
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v48:NilClass = Const Value(nil)
          PushInlineFrame v19 (0x1038)
          CheckInterrupts
          v43:Fixnum[42] = Const Value(42)
          PopInlineFrame
          Return v43
        ");
    }

    #[test]
    fn test_send_with_non_nil_block_arg() {
        eval(r#"
            def foo = 42

            def test
              block = :to_s
              foo(&block)
            end
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
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
          v13:StaticSymbol[:to_s] = Const Value(VALUE(0x1000))
          v19:BasicObject = Send v8, &block, :foo, v13 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_send_with_statically_nil_block_arg() {
        eval(r#"
            def foo = 42

            def test
              block = nil
              foo(&block)
            end
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
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
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v27:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v8, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v28:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_send_with_monomorphically_nil_block_arg() {
        eval(r#"
            def foo = 42

            def test(&block)
              foo(&block)
            end
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
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
          v17:CPtr = GetEP 0
          v18:CUInt64 = LoadField v17, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v19:CBool = IsBlockParamModified v18
          CondBranch v19, bb4(), bb5()
        bb4():
          v21:BasicObject = LoadField v17, :block@0x1002
          Jump bb6(v21, v21)
        bb5():
          v23:CInt64 = LoadField v17, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v24:CInt64[0] = GuardBitEquals v23, CInt64(0) recompile
          v25:NilClass = Const Value(nil)
          Jump bb6(v25, v10)
        bb6(v15:BasicObject, v16:BasicObject):
          v34:NilClass = GuardBitEquals v15, Value(nil) recompile
          PatchPoint MethodRedefined(Object@0x1008, foo@0x1010, cme:0x1018)
          v37:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v38:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v38
        ");
    }

    #[test]
    fn test_inline_attr_reader_constant() {
        eval("
            class C
              attr_reader :foo
            end

            O = C.new
            def test = O.foo
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
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
          PatchPoint StableConstantNames(0x1000, O)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v24:CShape = LoadField v12, :shape_id@0x1048
          v25:CShape[0x1049] = GuardBitEquals v24, CShape(0x1049) recompile
          v26:NilClass = Const Value(nil)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_inline_attr_accessor_constant() {
        eval("
            class C
              attr_accessor :foo
            end

            O = C.new
            def test = O.foo
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
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
          PatchPoint StableConstantNames(0x1000, O)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v24:CShape = LoadField v12, :shape_id@0x1048
          v25:CShape[0x1049] = GuardBitEquals v24, CShape(0x1049) recompile
          v26:NilClass = Const Value(nil)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_inline_attr_reader() {
        eval("
            class C
              attr_reader :foo
            end

            def test(o) = o.foo
            test C.new
            test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v25:CShape = LoadField v23, :shape_id@0x1040
          v26:CShape[0x1041] = GuardBitEquals v25, CShape(0x1041) recompile
          v27:NilClass = Const Value(nil)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_inline_attr_accessor() {
        eval("
            class C
              attr_accessor :foo
            end

            def test(o) = o.foo
            test C.new
            test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v25:CShape = LoadField v23, :shape_id@0x1040
          v26:CShape[0x1041] = GuardBitEquals v25, CShape(0x1041) recompile
          v27:NilClass = Const Value(nil)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_inline_attr_accessor_set() {
        eval("
            class C
              attr_accessor :foo
            end

            def test(o) = o.foo = 5
            test C.new
            test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v17:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1008, foo=@0x1010, cme:0x1018)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v30:CShape = LoadField v28, :shape_id@0x1040
          v31:CShape[0x1041] = GuardBitEquals v30, CShape(0x1041)
          StoreField v28, :@foo@0x1042, v17
          WriteBarrier v28, v17
          v34:CShape[0x1043] = Const CShape(0x1043)
          StoreField v28, :shape_id@0x1040, v34
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_inline_attr_writer_set() {
        eval("
            class C
              attr_writer :foo
            end

            def test(o) = o.foo = 5
            test C.new
            test C.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v17:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1008, foo=@0x1010, cme:0x1018)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v30:CShape = LoadField v28, :shape_id@0x1040
          v31:CShape[0x1041] = GuardBitEquals v30, CShape(0x1041)
          StoreField v28, :@foo@0x1042, v17
          WriteBarrier v28, v17
          v34:CShape[0x1043] = Const CShape(0x1043)
          StoreField v28, :shape_id@0x1040, v34
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_inline_struct_aref_embedded() {
        eval(r#"
            C = Struct.new(:foo)
            def test(o) = o.foo
            test C.new
            test C.new
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v24:BasicObject = LoadField v23, :foo@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_inline_struct_aref_heap() {
        eval(r#"
            C = Struct.new(*(0..1000).map {|i| :"a#{i}"}, :foo)
            def test(o) = o.foo
            test C.new
            test C.new
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v24:CPtr = LoadField v23, :as_heap@0x1040
          v25:BasicObject = LoadField v24, :foo@0x1041
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_elide_struct_aref() {
        eval(r#"
            C = Struct.new(*(0..1000).map {|i| :"a#{i}"}, :foo)
            def test(o)
              o.foo
              5
            end
            test C.new
            test C.new
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v27:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v19:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_struct_aset_embedded() {
        eval(r#"
            C = Struct.new(:foo)
            def test(o, v) = o.foo = v
            value = Object.new
            test C.new, value
            test C.new, value
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          v4:BasicObject = LoadField v2, :v@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :o@1
          v9:BasicObject = LoadArg :v@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo=@0x1010, cme:0x1018)
          v31:ObjectSubclass[class_exact:C] = GuardType v12, ObjectSubclass[class_exact:C] recompile
          v32:CUInt64 = LoadField v31, :RBASIC_FLAGS@0x1040
          v33:CUInt64 = GuardNoBitsSet v32, RUBY_FL_FREEZE=CUInt64(2048)
          StoreField v31, :foo=@0x1041, v13
          WriteBarrier v31, v13
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_inline_struct_aset_heap() {
        eval(r#"
            C = Struct.new(*(0..1000).map {|i| :"a#{i}"}, :foo)
            def test(o, v) = o.foo = v
            value = Object.new
            test C.new, value
            test C.new, value
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          v4:BasicObject = LoadField v2, :v@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :o@1
          v9:BasicObject = LoadArg :v@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo=@0x1010, cme:0x1018)
          v31:ObjectSubclass[class_exact:C] = GuardType v12, ObjectSubclass[class_exact:C] recompile
          v32:CUInt64 = LoadField v31, :RBASIC_FLAGS@0x1040
          v33:CUInt64 = GuardNoBitsSet v32, RUBY_FL_FREEZE=CUInt64(2048)
          v34:CPtr = LoadField v31, :as_heap@0x1041
          StoreField v34, :foo=@0x1042, v13
          WriteBarrier v31, v13
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_array_reverse_returns_array() {
        eval(r#"
            def test = [].reverse
        "#);
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v21:ArrayExact = CCallWithFrame v10, :Array#reverse@0x1038
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_array_reverse_is_elidable() {
        eval(r#"
            def test
              [].reverse
              5
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v16:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_array_join_returns_string() {
        eval(r#"
            def test = [].join ","
        "#);
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
          v10:ArrayExact = NewArray
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:StringExact = StringCopy v12
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, join@0x1010, cme:0x1018)
          v24:StringExact = CCallVariadic v10, :Array#join@0x1040, v13
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_string_to_s_returns_string() {
        eval(r#"
            def test = "".to_s
        "#);
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
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_string_literal_to_s() {
        eval(r#"
            def test = "foo".to_s
        "#);
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
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_profiled_string_to_s() {
        eval(r#"
            def test(o) = o.to_s
            test "foo"
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          v24:StringExact = GuardType v10, StringExact recompile
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fixnum_to_s_returns_string() {
        eval(r#"
            def test(x) = x.to_s
            test 5
        "#);
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
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v23:Fixnum = GuardType v10, Fixnum recompile
          v24:StringExact = CCallVariadic v23, :Integer#to_s@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_bignum_to_s_returns_string() {
        eval(r#"
            def test(x) = x.to_s
            test (2**65)
        "#);
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
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v23:Bignum = GuardType v10, Bignum recompile
          v24:StringExact = CCallVariadic v23, :Integer#to_s@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_any_to_string_with_known_string_exact() {
        eval(r##"
            def test(x) = "#{x}"
            test 123
        "##);
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
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v18:Fixnum = GuardType v10, Fixnum
          PatchPoint MethodRedefined(Integer@0x1010, to_s@0x1018, cme:0x1020)
          v32:StringExact = CCallVariadic v18, :Integer#to_s@0x1048
          v23:StringExact = StringConcat v14, v32
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_array_aref_fixnum_literal() {
        eval("
            def test
              arr = [1, 2, 3]
              arr[0]
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:ArrayExact = ArrayDup v13
          v19:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v38:CInt64[0] = Const CInt64(0)
          v32:CInt64 = ArrayLength v14
          v33:CInt64[0] = GuardLess v38, v32
          v37:BasicObject = ArrayAref v14, v33
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_array_aref_fixnum_profiled() {
        eval("
            def test(arr, idx)
              arr[idx]
            end
            test([1, 2, 3], 0)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          v4:BasicObject = LoadField v2, :idx@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :arr@1
          v9:BasicObject = LoadArg :idx@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v29:ArrayExact = GuardType v12, ArrayExact recompile
          v30:Fixnum = GuardType v13, Fixnum
          v31:CInt64 = UnboxFixnum v30
          v32:CInt64 = ArrayLength v29
          v33:CInt64 = GuardLess v31, v32
          v34:CInt64 = AdjustBounds v33, v32
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64 = GuardGreaterEq v34, v35
          v37:BasicObject = ArrayAref v29, v36
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_array_aref_fixnum_array_subclass() {
        eval("
            class C < Array; end
            def test(arr, idx)
              arr[idx]
            end
            test(C.new([1, 2, 3]), 0)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          v4:BasicObject = LoadField v2, :idx@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :arr@1
          v9:BasicObject = LoadArg :idx@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, []@0x1010, cme:0x1018)
          v29:ArraySubclass[class_exact:C] = GuardType v12, ArraySubclass[class_exact:C] recompile
          v30:Fixnum = GuardType v13, Fixnum
          v31:CInt64 = UnboxFixnum v30
          v32:CInt64 = ArrayLength v29
          v33:CInt64 = GuardLess v31, v32
          v34:CInt64 = AdjustBounds v33, v32
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64 = GuardGreaterEq v34, v35
          v37:BasicObject = ArrayAref v29, v36
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_hash_aref_literal() {
        eval("
            def test
              arr = {1 => 3}
              arr[1]
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:HashExact = HashDup v13
          v19:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          v31:BasicObject = HashAref v14, v19
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_hash_aref_profiled() {
        eval("
            def test(hash, key)
              hash[key]
            end
            test({1 => 3}, 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          v4:BasicObject = LoadField v2, :key@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :hash@1
          v9:BasicObject = LoadArg :key@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          v29:HashExact = GuardType v12, HashExact recompile
          v30:BasicObject = HashAref v29, v13
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_no_optimize_hash_aref_subclass() {
        eval("
            class C < Hash; end
            def test(hash, key)
              hash[key]
            end
            test(C.new({0 => 3}), 0)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          v4:BasicObject = LoadField v2, :key@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :hash@1
          v9:BasicObject = LoadArg :key@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, []@0x1010, cme:0x1018)
          v29:HashSubclass[class_exact:C] = GuardType v12, HashSubclass[class_exact:C] recompile
          v30:BasicObject = CCallWithFrame v29, :Hash#[]@0x1040, v13
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_does_not_fold_hash_aref_with_frozen_hash() {
        eval("
            H = {a: 0}.freeze
            def test = H[:a]
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, H)
          v12:HashExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:StaticSymbol[:a] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(Hash@0x1018)
          PatchPoint MethodRedefined(Hash@0x1018, []@0x1020, cme:0x1028)
          v27:BasicObject = HashAref v12, v14
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_hash_aset_literal() {
        eval("
            def test
              h = {}
              h[1] = 3
            end
        ");
        assert_snapshot!(hir_string("test"), @"
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
          v13:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v22:Fixnum[1] = Const Value(1)
          v24:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []=@0x1008, cme:0x1010)
          HashAset v13, v22, v24
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_hash_aset_profiled() {
        eval("
            def test(hash, key, val)
              hash[key] = val
            end
            test({}, 0, 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          v4:BasicObject = LoadField v2, :key@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :hash@1
          v10:BasicObject = LoadArg :key@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []=@0x1010, cme:0x1018)
          v37:HashExact = GuardType v14, HashExact recompile
          HashAset v37, v15, v16
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_no_optimize_hash_aset_subclass() {
        eval("
            class C < Hash; end
            def test(hash, key, val)
              hash[key] = val
            end
            test(C.new, 0, 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          v4:BasicObject = LoadField v2, :key@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :hash@1
          v10:BasicObject = LoadArg :key@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, []=@0x1010, cme:0x1018)
          v37:HashSubclass[class_exact:C] = GuardType v14, HashSubclass[class_exact:C] recompile
          v38:BasicObject = CCallWithFrame v37, :Hash#[]=@0x1040, v15, v16
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_optimize_thread_current() {
        eval("
            def test = Thread.current
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Thread)
          v12:ClassSubclass[Thread@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Class@0x1010, current@0x1018, cme:0x1020)
          v23:CPtr = LoadEC
          v24:CPtr = LoadField v23, :thread_ptr@0x1048
          v25:BasicObject = LoadField v24, :self@0x1049
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_optimize_array_aset_literal() {
        eval("
            def test(arr)
              arr[1] = 10
            end
            test([])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []=@0x1010, cme:0x1018)
          v33:ArrayExact = GuardType v10, ArrayExact recompile
          v34:CUInt64 = LoadField v33, :RBASIC_FLAGS@0x1040
          v35:CUInt64 = GuardNoBitsSet v34, RUBY_FL_FREEZE=CUInt64(2048)
          v37:CUInt64 = GuardNoBitsSet v35, RUBY_ELTS_SHARED=CUInt64(4096)
          v46:CInt64[1] = Const CInt64(1)
          v39:CInt64 = ArrayLength v33
          v40:CInt64[1] = GuardLess v46, v39
          ArrayAset v33, v40, v19
          WriteBarrier v33, v19
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_optimize_array_aset_profiled() {
        eval("
            def test(arr, index, val)
              arr[index] = val
            end
            test([], 0, 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          v4:BasicObject = LoadField v2, :index@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :arr@1
          v10:BasicObject = LoadArg :index@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []=@0x1010, cme:0x1018)
          v37:ArrayExact = GuardType v14, ArrayExact recompile
          v38:Fixnum = GuardType v15, Fixnum
          v39:CUInt64 = LoadField v37, :RBASIC_FLAGS@0x1040
          v40:CUInt64 = GuardNoBitsSet v39, RUBY_FL_FREEZE=CUInt64(2048)
          v42:CUInt64 = GuardNoBitsSet v40, RUBY_ELTS_SHARED=CUInt64(4096)
          v43:CInt64 = UnboxFixnum v38
          v44:CInt64 = ArrayLength v37
          v45:CInt64 = GuardLess v43, v44
          v46:CInt64 = AdjustBounds v45, v44
          v47:CInt64[0] = Const CInt64(0)
          v48:CInt64 = GuardGreaterEq v46, v47
          ArrayAset v37, v48, v16
          WriteBarrier v37, v16
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_optimize_array_aset_array_subclass() {
        eval("
            class MyArray < Array; end
            def test(arr, index, val)
              arr[index] = val
            end
            a = MyArray.new
            test(a, 0, 1)
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          v4:BasicObject = LoadField v2, :index@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :arr@1
          v10:BasicObject = LoadArg :index@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(MyArray@0x1008)
          PatchPoint MethodRedefined(MyArray@0x1008, []=@0x1010, cme:0x1018)
          v37:ArraySubclass[class_exact:MyArray] = GuardType v14, ArraySubclass[class_exact:MyArray] recompile
          v38:BasicObject = CCallVariadic v37, :Array#[]=@0x1040, v15, v16
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_optimize_array_ltlt() {
        eval("
            def test(arr)
              arr << 1
            end
            test([])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, <<@0x1010, cme:0x1018)
          v27:ArrayExact = GuardType v10, ArrayExact recompile
          v28:CUInt64 = LoadField v27, :RBASIC_FLAGS@0x1040
          v29:CUInt64 = GuardNoBitsSet v28, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v27, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_array_push_single_arg() {
        eval("
            def test(arr)
              arr.push(1)
            end
            test([])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, push@0x1010, cme:0x1018)
          v26:ArrayExact = GuardType v10, ArrayExact recompile
          v27:CUInt64 = LoadField v26, :RBASIC_FLAGS@0x1040
          v28:CUInt64 = GuardNoBitsSet v27, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v26, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_do_not_optimize_array_push_multi_arg() {
        eval("
            def test(arr)
              arr.push(1,2,3)
            end
            test([])
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          v17:Fixnum[2] = Const Value(2)
          v19:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, push@0x1010, cme:0x1018)
          v30:ArrayExact = GuardType v10, ArrayExact recompile
          v31:BasicObject = CCallVariadic v30, :Array#push@0x1040, v15, v17, v19
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_optimize_array_push_with_array_subclass() {
        eval("
            class PushSubArray < Array
              def <<(val) = super
            end
            test = PushSubArray.new
            test << 1
        ");
        assert_snapshot!(hir_string_proc("PushSubArray.new.method(:<<)"), @"
        fn <<@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :val@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :val@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Array@0x1008, <<@0x1010, cme:0x1018)
          v23:CPtr = GetEP 0
          v24:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v27:FalseClass = GuardBitEquals v26, Value(false)
          v28:Array = GuardType v9, Array
          v29:CUInt64 = LoadField v28, :RBASIC_FLAGS@0x1051
          v30:CUInt64 = GuardNoBitsSet v29, RUBY_FL_FREEZE=CUInt64(2048)
          ArrayPush v28, v10
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_array_pop_with_array_subclass() {
        eval("
            class PopSubArray < Array
              def pop = super
            end
            test = PopSubArray.new([1])
            test.pop
        ");
        assert_snapshot!(hir_string_proc("PopSubArray.new.method(:pop)"), @"
        fn pop@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, pop@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:Array = GuardType v6, Array
          v24:CUInt64 = LoadField v23, :RBASIC_FLAGS@0x1049
          v25:CUInt64 = GuardNoBitsSet v24, RUBY_FL_FREEZE=CUInt64(2048)
          v27:CUInt64 = GuardNoBitsSet v25, RUBY_ELTS_SHARED=CUInt64(4096)
          v28:BasicObject = ArrayPop v23
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_array_aref_with_array_subclass_and_fixnum() {
        eval("
            class ArefSubArray < Array
              def [](idx) = super
            end
            test = ArefSubArray.new([1])
            test[0]
        ");
        assert_snapshot!(hir_string_proc("ArefSubArray.new.method(:[])"), @"
        fn []@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :idx@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :idx@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v23:CPtr = GetEP 0
          v24:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v27:FalseClass = GuardBitEquals v26, Value(false)
          v28:Array = GuardType v9, Array
          v29:Fixnum = GuardType v10, Fixnum
          v30:CInt64 = UnboxFixnum v29
          v31:CInt64 = ArrayLength v28
          v32:CInt64 = GuardLess v30, v31
          v33:CInt64 = AdjustBounds v32, v31
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64 = GuardGreaterEq v33, v34
          v36:BasicObject = ArrayAref v28, v35
          CheckInterrupts
          Return v36
        ");
    }

    #[test]
    fn test_dont_optimize_array_aref_with_array_subclass_and_non_fixnum() {
        eval("
            class ArefSubArrayRange < Array
              def [](idx) = super
            end
            test = ArefSubArrayRange.new([1, 2, 3])
            test[0..1]
        ");
        assert_snapshot!(hir_string_proc("ArefSubArrayRange.new.method(:[])"), @"
        fn []@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :idx@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :idx@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v23:CPtr = GetEP 0
          v24:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v27:FalseClass = GuardBitEquals v26, Value(false)
          v28:BasicObject = CCallVariadic v9, :Array#[]@0x1058, v10
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_array_length() {
        eval("
            def test(arr) = arr.length
            test([])
        ");
        assert_contains_opcode("test", YARVINSN_opt_length);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, length@0x1010, cme:0x1018)
          v25:ArrayExact = GuardType v10, ArrayExact recompile
          v26:CInt64 = ArrayLength v25
          v27:Fixnum = BoxFixnum v26
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_array_size() {
        eval("
            def test(arr) = arr.size
            test([])
        ");
        assert_contains_opcode("test", YARVINSN_opt_size);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :arr@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :arr@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, size@0x1010, cme:0x1018)
          v25:ArrayExact = GuardType v10, ArrayExact recompile
          v26:CInt64 = ArrayLength v25
          v27:Fixnum = BoxFixnum v26
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_regexpmatch2() {
        eval(r#"
            def test(s) = s =~ /a/
            test("foo")
        "#);
        assert_contains_opcode("test", YARVINSN_opt_regexpmatch2);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:RegexpExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, =~@0x1018, cme:0x1020)
          v27:StringExact = GuardType v10, StringExact recompile
          v28:BasicObject = CCallWithFrame v27, :String#=~@0x1048, v15
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_string_getbyte_fixnum() {
        eval(r#"
            def test(s, i) = s.getbyte(i)
            test("foo", 0)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :i@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:BasicObject = LoadArg :i@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, getbyte@0x1010, cme:0x1018)
          v28:StringExact = GuardType v12, StringExact recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:CInt64 = UnboxFixnum v29
          v31:CInt64 = LoadField v28, :len@0x1040
          v32:CInt64 = GuardLess v30, v31
          v33:CInt64 = AdjustBounds v32, v31
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64 = GuardGreaterEq v33, v34
          v36:Fixnum = StringGetbyte v28, v35
          CheckInterrupts
          Return v36
        ");
    }

    #[test]
    fn test_elide_string_getbyte_fixnum() {
        eval(r#"
            def test(s, i)
              s.getbyte(i)
              5
            end
            test("foo", 0)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :i@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:BasicObject = LoadArg :i@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, getbyte@0x1010, cme:0x1018)
          v32:StringExact = GuardType v12, StringExact recompile
          v33:Fixnum = GuardType v13, Fixnum
          v34:CInt64 = UnboxFixnum v33
          v35:CInt64 = LoadField v32, :len@0x1040
          v36:CInt64 = GuardLess v34, v35
          v37:CInt64 = AdjustBounds v36, v35
          v38:CInt64[0] = Const CInt64(0)
          v39:CInt64 = GuardGreaterEq v37, v38
          v23:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_optimize_string_setbyte_fixnum() {
        eval(r#"
            def test(s, idx, val)
                s.setbyte(idx, val)
            end
            test("foo", 0, 127)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :idx@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :s@1
          v10:BasicObject = LoadArg :idx@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, setbyte@0x1010, cme:0x1018)
          v32:StringExact = GuardType v14, StringExact recompile
          v33:Fixnum = GuardType v15, Fixnum
          v34:Fixnum = GuardType v16, Fixnum
          v35:CInt64 = UnboxFixnum v33
          v36:CInt64 = LoadField v32, :len@0x1040
          v37:CInt64 = GuardLess v35, v36
          v38:CInt64 = AdjustBounds v37, v36
          v39:CInt64[0] = Const CInt64(0)
          v40:CInt64 = GuardGreaterEq v38, v39
          v41:CUInt64 = LoadField v32, :RBASIC_FLAGS@0x1041
          v42:CUInt64 = GuardNoBitsSet v41, RUBY_FL_FREEZE=CUInt64(2048)
          v43:Fixnum = StringSetbyteFixnum v32, v33, v34
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_optimize_string_subclass_setbyte_fixnum() {
        eval(r#"
            class MyString < String
            end
            def test(s, idx, val)
                s.setbyte(idx, val)
            end
            test(MyString.new('foo'), 0, 127)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :idx@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :s@1
          v10:BasicObject = LoadArg :idx@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(MyString@0x1008)
          PatchPoint MethodRedefined(MyString@0x1008, setbyte@0x1010, cme:0x1018)
          v32:StringSubclass[class_exact:MyString] = GuardType v14, StringSubclass[class_exact:MyString] recompile
          v33:Fixnum = GuardType v15, Fixnum
          v34:Fixnum = GuardType v16, Fixnum
          v35:CInt64 = UnboxFixnum v33
          v36:CInt64 = LoadField v32, :len@0x1040
          v37:CInt64 = GuardLess v35, v36
          v38:CInt64 = AdjustBounds v37, v36
          v39:CInt64[0] = Const CInt64(0)
          v40:CInt64 = GuardGreaterEq v38, v39
          v41:CUInt64 = LoadField v32, :RBASIC_FLAGS@0x1041
          v42:CUInt64 = GuardNoBitsSet v41, RUBY_FL_FREEZE=CUInt64(2048)
          v43:Fixnum = StringSetbyteFixnum v32, v33, v34
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_do_not_optimize_string_setbyte_non_fixnum() {
        eval(r#"
            def test(s, idx, val)
                s.setbyte(idx, val)
            end
            test("foo", 0, 3.14)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :idx@0x1001
          v5:BasicObject = LoadField v2, :val@0x1002
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :s@1
          v10:BasicObject = LoadArg :idx@2
          v11:BasicObject = LoadArg :val@3
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, setbyte@0x1010, cme:0x1018)
          v32:StringExact = GuardType v14, StringExact recompile
          v33:BasicObject = CCallWithFrame v32, :String#setbyte@0x1040, v15, v16
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_specialize_string_empty() {
        eval(r#"
            def test(s)
              s.empty?
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, empty?@0x1010, cme:0x1018)
          v25:StringExact = GuardType v10, StringExact recompile
          v26:CInt64 = LoadField v25, :len@0x1040
          v27:CInt64[0] = Const CInt64(0)
          v28:CBool = IsBitEqual v26, v27
          v29:BoolExact = BoxBool v28
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_eliminate_string_empty() {
        eval(r#"
            def test(s)
              s.empty?
              4
            end
            test("this should get removed")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, empty?@0x1010, cme:0x1018)
          v29:StringExact = GuardType v10, StringExact recompile
          v20:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_inline_integer_succ_with_fixnum() {
        eval("
            def test(x) = x.succ
            test(4)
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
          PatchPoint MethodRedefined(Integer@0x1008, succ@0x1010, cme:0x1018)
          v24:Fixnum = GuardType v10, Fixnum recompile
          v25:Fixnum[1] = Const Value(1)
          v26:Fixnum = FixnumAdd v24, v25
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_inline_integer_succ_with_bignum() {
        eval("
            def test(x) = x.succ
            test(4 << 70)
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
          PatchPoint MethodRedefined(Integer@0x1008, succ@0x1010, cme:0x1018)
          v24:Bignum = GuardType v10, Bignum recompile
          v25:BasicObject = CCallWithFrame v24, :Integer#succ@0x1040
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_inline_integer_ltlt_with_known_fixnum() {
        eval("
            def test(x) = x << 5
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
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
          v15:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1008, <<@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:Fixnum = FixnumLShift v26, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_negative() {
        eval("
            def test(x) = x << -5
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
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
          v15:Fixnum[-5] = Const Value(-5)
          PatchPoint MethodRedefined(Integer@0x1008, <<@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:BasicObject = CCallWithFrame v26, :Integer#<<@0x1040, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_out_of_range() {
        eval("
            def test(x) = x << 64
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
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
          v15:Fixnum[64] = Const Value(64)
          PatchPoint MethodRedefined(Integer@0x1008, <<@0x1010, cme:0x1018)
          v26:Fixnum = GuardType v10, Fixnum recompile
          v27:BasicObject = CCallWithFrame v26, :Integer#<<@0x1040, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_unknown_fixnum() {
        eval("
            def test(x, y) = x << y
            test(4, 5)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
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
          PatchPoint MethodRedefined(Integer@0x1008, <<@0x1010, cme:0x1018)
          v28:Fixnum = GuardType v12, Fixnum recompile
          v29:BasicObject = CCallWithFrame v28, :Integer#<<@0x1040, v13
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_inline_integer_gtgt_with_known_fixnum() {
        eval("
            def test(x) = x >> 5
            test(4)
        ");
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
          v15:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1008, >>@0x1010, cme:0x1018)
          v25:Fixnum = GuardType v10, Fixnum recompile
          v26:Fixnum = FixnumRShift v25, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_negative() {
        eval("
            def test(x) = x >> -5
            test(4)
        ");
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
          v15:Fixnum[-5] = Const Value(-5)
          PatchPoint MethodRedefined(Integer@0x1008, >>@0x1010, cme:0x1018)
          v25:Fixnum = GuardType v10, Fixnum recompile
          v26:BasicObject = CCallWithFrame v25, :Integer#>>@0x1040, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_out_of_range() {
        eval("
            def test(x) = x >> 64
            test(4)
        ");
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
          v15:Fixnum[64] = Const Value(64)
          PatchPoint MethodRedefined(Integer@0x1008, >>@0x1010, cme:0x1018)
          v25:Fixnum = GuardType v10, Fixnum recompile
          v26:BasicObject = CCallWithFrame v25, :Integer#>>@0x1040, v15
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_unknown_fixnum() {
        eval("
            def test(x, y) = x >> y
            test(4, 5)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, >>@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v12, Fixnum recompile
          v28:BasicObject = CCallWithFrame v27, :Integer#>>@0x1040, v13
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_string_append() {
        eval(r#"
            def test(x, y) = x << y
            test("iron", "fish")
        "#);
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
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, <<@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:String = GuardType v13, String
          v31:StringExact = StringAppend v29, v30
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_optimize_string_append_codepoint() {
        eval(r#"
            def test(x, y) = x << y
            test("iron", 4)
        "#);
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
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, <<@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:Fixnum = GuardType v13, Fixnum
          v31:StringExact = StringAppendCodepoint v29, v30
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_optimize_string_append_string_subclass() {
        eval(r#"
            class MyString < String
            end
            def test(x, y) = x << y
            test("iron", MyString.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, <<@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:String = GuardType v13, String
          v31:StringExact = StringAppend v29, v30
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_do_not_optimize_string_subclass_append_string() {
        eval(r#"
            class MyString < String
            end
            def test(x, y) = x << y
            test(MyString.new, "iron")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
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
          PatchPoint NoSingletonClass(MyString@0x1008)
          PatchPoint MethodRedefined(MyString@0x1008, <<@0x1010, cme:0x1018)
          v29:StringSubclass[class_exact:MyString] = GuardType v12, StringSubclass[class_exact:MyString] recompile
          v30:BasicObject = CCallWithFrame v29, :String#<<@0x1040, v13
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_dont_optimize_string_append_non_string() {
        eval(r#"
            def test = "iron" << :a
        "#);
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
          v11:StringExact = StringCopy v10
          v13:StaticSymbol[:a] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, <<@0x1018, cme:0x1020)
          v25:BasicObject = CCallWithFrame v11, :String#<<@0x1048, v13
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_dont_optimize_when_passing_too_many_args() {
        eval(r#"
            public def foo(lead, opt=raise) = opt
            def test = 0.foo(3, 3, 3)
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
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[3] = Const Value(3)
          v14:Fixnum[3] = Const Value(3)
          v16:Fixnum[3] = Const Value(3)
          v18:BasicObject = Send v10, :foo, v12, v14, v16 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_optimize_string_ascii_only_p() {
        eval(r#"
            def test(x) = x.ascii_only?
            test("iron")
        "#);
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
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ascii_only?@0x1010, cme:0x1018)
          v23:StringExact = GuardType v10, StringExact recompile
          v24:CUInt64 = LoadField v23, :RBASIC_FLAGS@0x1040
          v25:CUInt64[3145728] = Const CUInt64(3145728)
          v26:CInt64 = IntAnd v24, v25
          v27:CInt64[1048576] = Const CInt64(1048576)
          v28:CInt64 = GuardGreaterEq v26, v27
          v29:CInt64[1048576] = Const CInt64(1048576)
          v30:CBool = IsBitEqual v28, v29
          v31:BoolExact = BoxBool v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_dont_optimize_when_passing_too_few_args() {
        eval(r#"
            public def foo(lead, opt=raise) = opt
            def test = 0.foo
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
          v10:Fixnum[0] = Const Value(0)
          v12:BasicObject = Send v10, :foo # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_dont_inline_integer_succ_with_args() {
        eval("
            def test = 4.succ 1
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
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[1] = Const Value(1)
          v14:BasicObject = Send v10, :succ, v12 # SendFallbackReason: Argument count does not match parameter count
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_inline_integer_xor_with_fixnum() {
        eval("
            def test(x, y) = x ^ y
            test(1, 2)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, ^@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v12, Fixnum recompile
          v28:Fixnum = GuardType v13, Fixnum
          v29:Fixnum = FixnumXor v27, v28
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_eliminate_integer_xor() {
        eval(r#"
            def test(x, y)
              x ^ y
              42
            end
            test(1, 2)
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
          PatchPoint MethodRedefined(Integer@0x1008, ^@0x1010, cme:0x1018)
          v31:Fixnum = GuardType v12, Fixnum recompile
          v32:Fixnum = GuardType v13, Fixnum
          v23:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_bignum_lhs() {
        eval("
            def test(x, y) = x ^ y
            test(4 << 70, 1)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, ^@0x1010, cme:0x1018)
          v27:Bignum = GuardType v12, Bignum recompile
          v28:BasicObject = CCallWithFrame v27, :Integer#^@0x1040, v13
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_bignum_rhs() {
        eval("
            def test(x, y) = x ^ y
            test(1, 4 << 70)
        ");
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
          PatchPoint MethodRedefined(Integer@0x1008, ^@0x1010, cme:0x1018)
          v27:Fixnum = GuardType v12, Fixnum recompile
          v28:BasicObject = CCallWithFrame v27, :Integer#^@0x1040, v13
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_boolean() {
        eval("
            def test(x, y) = x ^ y
            test(true, 0)
        ");
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
          PatchPoint MethodRedefined(TrueClass@0x1008, ^@0x1010, cme:0x1018)
          v27:TrueClass = GuardType v12, TrueClass recompile
          v28:BasicObject = CCallWithFrame v27, :TrueClass#^@0x1040, v13
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_args() {
        eval("
            def test(x, y) = x.^()
        ");
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
          SideExit NoProfileSend recompile
        ");
    }

    #[test]
    fn test_specialize_hash_size() {
        eval("
            def test(hash) = hash.size
            test({foo: 3, bar: 1, baz: 4})
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :hash@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, size@0x1010, cme:0x1018)
          v25:HashExact = GuardType v10, HashExact recompile
          v26:Fixnum = CCall v25, :Hash#size@0x1040
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_eliminate_hash_size() {
        eval("
            def test(hash)
                hash.size
                5
            end
            test({foo: 3, bar: 1, baz: 4})
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :hash@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :hash@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, size@0x1010, cme:0x1018)
          v29:HashExact = GuardType v10, HashExact recompile
          v20:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_true() {
        eval(r#"
            class C
              def foo; end
            end
            def test(o) = o.respond_to?(:foo)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v30:TrueClass = Const Value(true)
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_false_no_method() {
        eval(r#"
            class C
            end
            def test(o) = o.respond_to?(:foo)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, respond_to_missing?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1078, cme:0x1080)
          v32:FalseClass = Const Value(false)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_false_default_private() {
        eval(r#"
            class C
                private
                def foo; end
            end
            def test(o) = o.respond_to?(:foo)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v30:FalseClass = Const Value(false)
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_false_private() {
        eval(r#"
            class C
                private
                def foo; end
            end
            def test(o) = o.respond_to?(:foo, false)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          v17:FalseClass = Const Value(false)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:FalseClass = Const Value(false)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_falsy_private() {
        eval(r#"
            class C
                private
                def foo; end
            end
            def test(o) = o.respond_to?(:foo, nil)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          v17:NilClass = Const Value(nil)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:FalseClass = Const Value(false)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_true_private() {
        eval(r#"
            class C
                private
                def foo; end
            end
            def test(o) = o.respond_to?(:foo, true)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          v17:TrueClass = Const Value(true)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_truthy() {
        eval(r#"
            class C
              def foo; end
            end
            def test(o) = o.respond_to?(:foo, 4)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          v17:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_p_falsy() {
        eval(r#"
            class C
              def foo; end
            end
            def test(o) = o.respond_to?(:foo, nil)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          v17:NilClass = Const Value(nil)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v28:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_optimize_respond_to_missing() {
        eval(r#"
            class C
            end
            def test(o) = o.respond_to?(:foo)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          PatchPoint MethodRedefined(C@0x1010, respond_to_missing?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1078, cme:0x1080)
          v32:FalseClass = Const Value(false)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_do_not_optimize_redefined_respond_to_missing() {
        eval(r#"
            class C
                def respond_to_missing?(method, include_private = false)
                    true
                end
            end
            def test(o) = o.respond_to?(:foo)
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, respond_to?@0x1018, cme:0x1020)
          v26:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v27:BasicObject = CCallVariadic v26, :Kernel#respond_to?@0x1048, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putself() {
        eval(r#"
            def callee = self
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_string() {
        eval(r#"
            # frozen_string_literal: true
            def callee = "abc"
            def test = callee
            test
        "#);
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:StringExact[VALUE(0x1038)] = Const Value(VALUE(0x1038))
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putnil() {
        eval(r#"
            def callee = nil
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:NilClass = Const Value(nil)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_true() {
        eval(r#"
            def callee = true
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:TrueClass = Const Value(true)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_false() {
        eval(r#"
            def callee = false
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:FalseClass = Const Value(false)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_zero() {
        eval(r#"
            def callee = 0
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_one() {
        eval(r#"
            def callee = 1
            def test = callee
            test
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
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_parameter() {
        eval(r#"
            def callee(x) = x
            def test = callee 3
            test
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_last_parameter() {
        eval(r#"
            def callee(x, y, z) = z
            def test = callee 1, 2, 3
            test
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v24:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_splat() {
        eval("
            def foo = itself

            def test
              # Use a local to inhibit compile.c peephole optimization to ensure callsites have VM_CALL_ARGS_SPLAT
              empty = []
              foo(*empty)
              ''.display(*empty)
              itself(*empty)
            end
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:6:
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
          v13:ArrayExact = NewArray
          v19:ArrayExact = ToArray v13
          v21:BasicObject = Send v8, :foo, v19 # SendFallbackReason: Complex argument passing
          v25:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v26:StringExact = StringCopy v25
          PatchPoint NoEPEscape(test)
          v31:ArrayExact = ToArray v13
          v33:BasicObject = Send v26, :display, v31 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          v41:ArrayExact = ToArray v13
          v43:BasicObject = Send v8, :itself, v41 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v43
        ");
    }

    #[test]
    fn test_inline_symbol_to_sym() {
        eval(r#"
            def test(o) = o.to_sym
            test :foo
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Symbol@0x1008, to_sym@0x1010, cme:0x1018)
          v22:StaticSymbol = GuardType v10, StaticSymbol recompile
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_integer_to_i() {
        eval(r#"
            def test(o) = o.to_i
            test 5
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1008, to_i@0x1010, cme:0x1018)
          v22:Fixnum = GuardType v10, Fixnum recompile
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_no_params() {
        // Passing a block to a method that doesn't use it falls back to the
        // interpreter so that unused block warnings are properly emitted.
        eval(r#"
            def callee = 123
            def test
              callee do
              end
            end
            test
        "#);
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
          v11:BasicObject = Send v6, 0x1000, :callee # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_one_param() {
        // Passing a block to a method that doesn't use it falls back to the
        // interpreter so that unused block warnings are properly emitted.
        eval(r#"
            def callee = 123
            def test
              callee do |_|
              end
            end
            test
        "#);
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
          v11:BasicObject = Send v6, 0x1000, :callee # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_multiple_params() {
        // Passing a block to a method that doesn't use it falls back to the
        // interpreter so that unused block warnings are properly emitted.
        eval(r#"
            def callee = 123
            def test
              callee do |_a, _b|
              end
            end
            test
        "#);
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
          v11:BasicObject = Send v6, 0x1000, :callee # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_no_inline_send_with_symbol_block() {
        eval(r#"
            def callee = 123
            public def the_block = 456
            def test
              callee(&:the_block)
            end
            puts test
        "#);
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
          v11:StaticSymbol[:the_block] = Const Value(VALUE(0x1000))
          v13:BasicObject = Send v6, &block, :callee, v11 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_profile_stack_skips_block_arg() {
        // Regression test: profile_stack must skip the &block arg on the stack when mapping
        // profiled operand types. Without the fix, the receiver type would be mapped to the
        // wrong stack slot, causing resolve_receiver_type to return NoProfile.
        // With the fix, the receiver type is correctly resolved and the send gets past type
        // resolution to hit the ARGS_BLOCKARG guard (ComplexArgPass) instead of NoProfile.
        eval("
            def test(&block) = [].map(&block)
            test { |x| x }; test { |x| x }
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
          v14:ArrayExact = NewArray
          v18:CPtr = GetEP 0
          v19:CUInt64 = LoadField v18, :VM_ENV_DATA_INDEX_FLAGS@0x1001
          v20:CBool = IsBlockParamModified v19
          CondBranch v20, bb4(), bb5()
        bb4():
          v22:BasicObject = LoadField v18, :block@0x1002
          Jump bb6(v22, v22)
        bb5():
          v24:CInt64 = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1003
          v25:CInt64 = GuardAnyBitSet v24, CUInt64(1) recompile
          v26:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1008))
          Jump bb6(v26, v10)
        bb6(v16:BasicObject, v17:BasicObject):
          v29:BasicObject = Send v14, &block, :map, v16 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_optimize_stringexact_eq_stringexact() {
        eval(r#"
            def test(l, r) = l == r
            test("a", "b")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:String = GuardType v13, String
          v31:BoolExact = StringEqual v29, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_optimize_string_eq_string() {
        eval(r#"
            class C < String
            end
            def test(l, r) = l == r
            test(C.new("a"), C.new("b"))
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, ==@0x1010, cme:0x1018)
          v29:StringSubclass[class_exact:C] = GuardType v12, StringSubclass[class_exact:C] recompile
          v30:String = GuardType v13, String
          v31:BoolExact = StringEqual v29, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_optimize_stringexact_eq_string() {
        eval(r#"
            class C < String
            end
            def test(l, r) = l == r
            test("a", C.new("b"))
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:String = GuardType v13, String
          v31:BoolExact = StringEqual v29, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_optimize_stringexact_eqq_stringexact() {
        eval(r#"
            def test(l, r) = l === r
            test("a", "b")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ===@0x1010, cme:0x1018)
          v28:StringExact = GuardType v12, StringExact recompile
          v29:String = GuardType v13, String
          v30:BoolExact = StringEqual v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_string_eqq_string() {
        eval(r#"
            class C < String
            end
            def test(l, r) = l === r
            test(C.new("a"), C.new("b"))
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, ===@0x1010, cme:0x1018)
          v28:StringSubclass[class_exact:C] = GuardType v12, StringSubclass[class_exact:C] recompile
          v29:String = GuardType v13, String
          v30:BoolExact = StringEqual v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_stringexact_eqq_string() {
        eval(r#"
            class C < String
            end
            def test(l, r) = l === r
            test("a", C.new("b"))
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :l@0x1000
          v4:BasicObject = LoadField v2, :r@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :l@1
          v9:BasicObject = LoadArg :r@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ===@0x1010, cme:0x1018)
          v28:StringExact = GuardType v12, StringExact recompile
          v29:String = GuardType v13, String
          v30:BoolExact = StringEqual v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_fold_string_equal_same_operand_true() {
        eval(r#"
            def test(s) = s == s
            test("x")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v26:StringExact = GuardType v10, StringExact recompile
          v29:TrueClass = Const Value(true)
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_fold_string_eqq_same_operand_true() {
        eval(r#"
            def test(s) = s === s
            test("x")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ===@0x1010, cme:0x1018)
          v25:StringExact = GuardType v10, StringExact recompile
          v28:TrueClass = Const Value(true)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_string_equal_frozen_local_same_operand_true() {
        eval(r#"
            def test
              str = "a".freeze
              str == str
            end

            test
            test
        "#);
        assert_snapshot!(hir_string("test"), @"
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v14:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v32:TrueClass = Const Value(true)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_fold_string_equal_frozen_distinct_literals_false() {
        eval(r#"
            def test
              "a".freeze == "b".freeze
            end

            test
            test
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
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, ==@0x1018, cme:0x1020)
          v28:FalseClass = Const Value(false)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_not_fold_string_equal_true_without_pragma() {
        eval(r#"
            def test
              "a" == "a"
            end

            test
            test
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:StringExact = StringCopy v13
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v27:BoolExact = StringEqual v11, v14
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_not_fold_string_equal_false_without_pragma() {
        eval(r#"
            def test
              "a" == "b"
            end

            test
            test
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          v13:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:StringExact = StringCopy v13
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, ==@0x1018, cme:0x1020)
          v27:BoolExact = StringEqual v11, v14
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_fold_string_equal_true_with_pragma() {
        eval(r#"
            # frozen_string_literal: true
            def test
              "a" == "a"
            end

            test
            test
        "#);
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v26:TrueClass = Const Value(true)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_string_equal_false_with_pragma() {
        eval(r#"
            # frozen_string_literal: true
            def test
              "a" == "b"
            end

            test
            test
        "#);
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
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, ==@0x1018, cme:0x1020)
          v26:FalseClass = Const Value(false)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_not_fold_string_equal_after_string_append_mutation() {
        eval(r#"
            def test
              a = "a"
              b = "a"
              a << "a"
              a == b
            end

            test
            test
        "#);
        assert_snapshot!(hir_string("test"), @"
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
          v16:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v17:StringExact = StringCopy v16
          v21:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v22:StringExact = StringCopy v21
          v27:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v28:StringExact = StringCopy v27
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, <<@0x1010, cme:0x1018)
          v50:StringExact = StringAppend v17, v28
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1040, cme:0x1048)
          v55:BoolExact = StringEqual v17, v22
          CheckInterrupts
          Return v55
        ");
    }

    #[test]
    fn test_not_fold_string_equal_distinct_objects() {
        eval(r#"
            def test(s, t) = s == t
            test("x", "x")
            test("x", "x")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :t@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:BasicObject = LoadArg :t@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, ==@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          v30:String = GuardType v13, String
          v31:BoolExact = StringEqual v29, v30
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_not_fold_string_equal_one_side_known_literal() {
        eval(r#"
            def test(s) = "a" == s
            test("a")
            test("a")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v14:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v15:StringExact = StringCopy v14
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, ==@0x1018, cme:0x1020)
          v29:String = GuardType v10, String
          v30:BoolExact = StringEqual v15, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn opt_neq_string_nil_falls_back_to_basic_object_neq() {
        eval(r#"
            def test(str)
              str != nil
            end

            test("x")
            test("x")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :str@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :str@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:NilClass = Const Value(nil)
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, !=@0x1010, cme:0x1018)
          v27:StringExact = GuardType v10, StringExact recompile
          v28:BoolExact = CCallWithFrame v27, :BasicObject#!=@0x1040, v15
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_inline_string_not_equal_distinct_objects() {
        eval(r#"
            def test(s, t) = s != t
            test("x", "x")
            test("x", "x")
        "#);
        assert_contains_opcode("test", YARVINSN_opt_neq);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :t@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:BasicObject = LoadArg :t@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, !=@0x1010, cme:0x1018)
          v29:StringExact = GuardType v12, StringExact recompile
          PatchPoint MethodRedefined(String@0x1008, ==@0x1040, cme:0x1048)
          v33:String = GuardType v13, String
          v34:BoolExact = StringEqual v29, v33
          v35:TrueClass = Const Value(true)
          v36:CBool = IsBitNotEqual v34, v35
          v37:BoolExact = BoxBool v36
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_fold_string_not_equal_same_operand_false() {
        eval(r#"
            def test(s) = s != s
            test("x")
            test("x")
        "#);
        assert_contains_opcode("test", YARVINSN_opt_neq);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, !=@0x1010, cme:0x1018)
          v26:StringExact = GuardType v10, StringExact recompile
          PatchPoint MethodRedefined(String@0x1008, ==@0x1040, cme:0x1048)
          v35:TrueClass = Const Value(true)
          v32:TrueClass = Const Value(true)
          v33:CBool = IsBitNotEqual v35, v32
          v34:BoolExact = BoxBool v33
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_specialize_string_size() {
        eval(r#"
            def test(s)
              s.size
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, size@0x1010, cme:0x1018)
          v25:StringExact = GuardType v10, StringExact recompile
          v26:Fixnum = CCall v25, :String#size@0x1040
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_elide_string_size() {
         eval(r#"
            def test(s)
              s.size
              5
            end
            test("asdf")
        "#);
       assert_snapshot!(hir_string("test"), @"
       fn test@<compiled>:3:
       bb1():
         EntryPoint interpreter
         v1:BasicObject = LoadSelf
         v2:CPtr = LoadSP
         v3:BasicObject = LoadField v2, :s@0x1000
         Jump bb3(v1, v3)
       bb2():
         EntryPoint JIT(0)
         v6:BasicObject = LoadArg :self@0
         v7:BasicObject = LoadArg :s@1
         Jump bb3(v6, v7)
       bb3(v9:BasicObject, v10:BasicObject):
         PatchPoint NoSingletonClass(String@0x1008)
         PatchPoint MethodRedefined(String@0x1008, size@0x1010, cme:0x1018)
         v29:StringExact = GuardType v10, StringExact recompile
         v20:Fixnum[5] = Const Value(5)
         CheckInterrupts
         Return v20
       ");
    }

    #[test]
    fn test_inline_string_bytesize() {
        eval(r#"
            def test(s)
              s.bytesize
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, bytesize@0x1010, cme:0x1018)
          v24:StringExact = GuardType v10, StringExact recompile
          v25:CInt64 = LoadField v24, :len@0x1040
          v26:Fixnum = BoxFixnum v25
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_elide_string_bytesize() {
        eval(r#"
            def test(s)
              s.bytesize
              5
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, bytesize@0x1010, cme:0x1018)
          v28:StringExact = GuardType v10, StringExact recompile
          v19:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_specialize_string_length() {
        eval(r#"
            def test(s)
              s.length
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, length@0x1010, cme:0x1018)
          v25:StringExact = GuardType v10, StringExact recompile
          v26:Fixnum = CCall v25, :String#length@0x1040
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_class_eqq() {
        eval(r#"
            def test(o) = String === o
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, String)
          v16:ClassSubclass[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint MethodRedefined(Class@0x1018, ===@0x1020, cme:0x1028)
          v30:BoolExact = IsA v10, v16
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_dont_specialize_module_eqq() {
        eval(r#"
            def test(o) = Kernel === o
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Kernel)
          v16:ModuleSubclass[Kernel@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint MethodRedefined(Module@0x1018, ===@0x1020, cme:0x1028)
          v30:BoolExact = CCall v16, :Module#===@0x1050, v10
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_specialize_is_a_class() {
        eval(r#"
            def test(o) = o.is_a?(String)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, String)
          v17:ClassSubclass[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, is_a?@0x1011, cme:0x1018)
          v28:StringExact = GuardType v10, StringExact recompile
          v29:BoolExact = IsA v28, v17
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_dont_specialize_is_a_module() {
        eval(r#"
            def test(o) = o.is_a?(Kernel)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Kernel)
          v17:ModuleSubclass[Kernel@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, is_a?@0x1020, cme:0x1028)
          v28:StringExact = GuardType v10, StringExact recompile
          v29:BasicObject = CCallWithFrame v28, :Kernel#is_a?@0x1050, v17
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_elide_is_a() {
        eval(r#"
            def test(o)
              o.is_a?(Integer)
              5
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Integer)
          v17:ClassSubclass[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, is_a?@0x1020, cme:0x1028)
          v32:StringExact = GuardType v10, StringExact recompile
          v23:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_elide_class_eqq() {
        eval(r#"
            def test(o)
              Integer === o
              5
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Integer)
          v16:ClassSubclass[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint MethodRedefined(Class@0x1018, ===@0x1020, cme:0x1028)
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_specialize_kind_of_class() {
        eval(r#"
            def test(o) = o.kind_of?(String)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, String)
          v17:ClassSubclass[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, kind_of?@0x1011, cme:0x1018)
          v28:StringExact = GuardType v10, StringExact recompile
          v29:BoolExact = IsA v28, v17
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_dont_specialize_kind_of_module() {
        eval(r#"
            def test(o) = o.kind_of?(Kernel)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:2:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Kernel)
          v17:ModuleSubclass[Kernel@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, kind_of?@0x1020, cme:0x1028)
          v28:StringExact = GuardType v10, StringExact recompile
          v29:BasicObject = CCallWithFrame v28, :Kernel#kind_of?@0x1050, v17
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_elide_kind_of() {
        eval(r#"
            def test(o)
              o.kind_of?(Integer)
              5
            end
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1008, Integer)
          v17:ClassSubclass[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, kind_of?@0x1020, cme:0x1028)
          v32:StringExact = GuardType v10, StringExact recompile
          v23:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_fold_is_a_true() {
        eval(r#"
            def test = 5.is_a?(Integer)
            test
        "#);
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Integer)
          v14:ClassSubclass[Integer@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Integer@0x1008, is_a?@0x1009, cme:0x1010)
          v26:TrueClass = Const Value(true)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_is_a_false() {
        eval(r#"
            def test = 5.is_a?(String)
            test
        "#);
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v14:ClassSubclass[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Integer@0x1010, is_a?@0x1018, cme:0x1020)
          v26:FalseClass = Const Value(false)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_is_a_array_subclass_folds_to_true() {
        eval(r#"
            class C < Array; end
            O = C.new
            def test = O.is_a?(Array)
            test
        "#);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, O)
          v12:ArraySubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Array)
          v16:ClassSubclass[Array@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint NoSingletonClass(C@0x1020)
          PatchPoint MethodRedefined(C@0x1020, is_a?@0x1028, cme:0x1030)
          v29:TrueClass = Const Value(true)
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_is_a_user_defined_class_folds_to_true() {
        eval(r#"
            class C; end
            O = C.new
            def test = O.is_a?(C)
            test
        "#);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, O)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, C)
          v16:ClassSubclass[C@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint NoSingletonClass(C@0x1018)
          PatchPoint MethodRedefined(C@0x1018, is_a?@0x1019, cme:0x1020)
          v29:TrueClass = Const Value(true)
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_is_a_symbol_folds_to_true() {
        eval(r#"
            O = :my_static_symbol
            def test = O.is_a?(Symbol)
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, O)
          v12:StaticSymbol[:my_static_symbol] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Symbol)
          v16:ClassSubclass[Symbol@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint MethodRedefined(Symbol@0x1018, is_a?@0x1019, cme:0x1020)
          v28:TrueClass = Const Value(true)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn counting_complex_feature_use_for_fallback() {
        eval("
            define_method(:fancy) { |_a, *_b, kw: 100, **kw_rest, &block| }
            def test = fancy(1)
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
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:BasicObject = Send v6, :fancy, v11 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn call_method_forwardable_param() {
        eval("
           def forwardable(...) = itself(...)
           def call_forwardable = forwardable
           call_forwardable
        ");
        assert_snapshot!(hir_string("call_forwardable"), @"
        fn call_forwardable@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          v11:BasicObject = Send v6, :forwardable # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_elide_string_length() {
        eval(r#"
            def test(s)
              s.length
              4
            end
            test("this should get removed")
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :s@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, length@0x1010, cme:0x1018)
          v29:StringExact = GuardType v10, StringExact recompile
          v20:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_fold_self_class_respond_to_true() {
        eval(r#"
            class C
              class << self
                attr_accessor :_lex_actions
                private :_lex_actions, :_lex_actions=
              end
              self._lex_actions = [1, 2, 3]
              def initialize
                if self.class.respond_to?(:_lex_actions, true)
                  :CORRECT
                else
                  :oh_no_wrong
                end
              end
            end
            C.new  # warm up
            TEST = C.instance_method(:initialize)
        "#);
        assert_snapshot!(hir_string_proc("TEST"), @"
        fn initialize@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          v43:ObjectSubclass[class_exact:C] = GuardType v6, ObjectSubclass[class_exact:C] recompile
          v44:ClassSubclass[C@0x1000] = Const Value(VALUE(0x1000))
          v13:StaticSymbol[:_lex_actions] = Const Value(VALUE(0x1038))
          v15:TrueClass = Const Value(true)
          PatchPoint MethodRedefined(Class@0x1040, respond_to?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(Class@0x1040, _lex_actions@0x1078, cme:0x1080)
          v50:TrueClass = Const Value(true)
          CheckInterrupts
          v26:StaticSymbol[:CORRECT] = Const Value(VALUE(0x10a8))
          Return v26
        ");
    }

    #[test]
    fn test_fold_self_class_name() {
        eval(r#"
            class C; end
            def test(o) = o.class.name
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, class@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v26:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Class@0x1040, name@0x1048, cme:0x1050)
          v30:StringExact|NilClass = CCall v26, :Module#name@0x1078
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_fold_kernel_class() {
        eval(r#"
            class C; end
            def test(o) = o.class
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, class@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:C] = GuardType v10, ObjectSubclass[class_exact:C] recompile
          v24:ClassSubclass[C@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_fold_fixnum_class() {
        eval(r#"
            def test = 5.class
            test
        "#);
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, class@0x1008, cme:0x1010)
          v20:ClassSubclass[Integer@0x1000] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_fold_singleton_class() {
        eval(r#"
            def test = self.class
            test
        "#);
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
          PatchPoint MethodRedefined(Object@0x1000, class@0x1008, cme:0x1010)
          v18:ObjectSubclass[class_exact*:Object@VALUE(0x1000)] = GuardType v6, ObjectSubclass[class_exact*:Object@VALUE(0x1000)] recompile
          v19:ClassSubclass[Object@0x1038] = Const Value(VALUE(0x1038))
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_print_nil_module_name() {
        eval(r#"
            X = [Module.new].freeze
            def test = X[0]
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, X)
          v12:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, []@0x1018, cme:0x1020)
          v36:ModuleExact[VALUE(0x1048)] = Const Value(VALUE(0x1048))
          CheckInterrupts
          Return v36
        ");
    }

    #[test]
    fn no_load_from_ep_right_after_entrypoint() {
      let formatted = eval("
          def read_nil_local(a, _b, _c)
            formatted ||= a
            @formatted = formatted
            -> { formatted } # the environment escapes
          end

          def call
            puts [], [], [], []     # fill VM stack with junk
            read_nil_local(true, 1, 1) # expected direct send
          end

          call # profile
          call # compile
          @formatted
       ");
       assert_eq!(Qtrue, formatted, "{}", formatted.obj_info());
       assert_snapshot!(hir_string("read_nil_local"), @"
       fn read_nil_local@<compiled>:3:
       bb1():
         EntryPoint interpreter
         v1:BasicObject = LoadSelf
         v2:CPtr = LoadSP
         v3:BasicObject = LoadField v2, :a@0x1000
         v4:BasicObject = LoadField v2, :_b@0x1001
         v5:BasicObject = LoadField v2, :_c@0x1002
         v6:NilClass = Const Value(nil)
         Jump bb3(v1, v3, v4, v5, v6)
       bb2():
         EntryPoint JIT(0)
         v9:BasicObject = LoadArg :self@0
         v10:BasicObject = LoadArg :a@1
         v11:CPtr = GetEP 0
         StoreField v11, :a@0x1001, v10
         v13:BasicObject = LoadArg :_b@2
         StoreField v11, :_b@0x1002, v13
         v15:BasicObject = LoadArg :_c@3
         StoreField v11, :_c@0x1003, v15
         v17:NilClass = Const Value(nil)
         StoreField v11, :formatted@0x1004, v17
         Jump bb3(v9, v10, v13, v15, v17)
       bb3(v20:BasicObject, v21:BasicObject, v22:BasicObject, v23:BasicObject, v24:NilClass):
         CheckInterrupts
         SetLocal :formatted, l0, EP@3, v21
         PatchPoint SingleRactorMode
         SetIvar v20, :@formatted, v21
         v52:ClassSubclass[VMFrozenCore] = Const Value(VALUE(0x1008))
         PatchPoint MethodRedefined(Class@0x1010, lambda@0x1018, cme:0x1020)
         v68:BasicObject = CCallWithFrame v52, :RubyVM::FrozenCore.lambda@0x1048, block=0x1050
         v55:CPtr = GetEP 0
         v56:BasicObject = LoadField v55, :a@0x1001
         v57:BasicObject = LoadField v55, :_b@0x1002
         v58:BasicObject = LoadField v55, :_c@0x1003
         v59:BasicObject = LoadField v55, :formatted@0x1004
         CheckInterrupts
         Return v68
       ");
    }

    #[test]
    fn test_fold_load_field_frozen_constant_object() {
        // Basic case: frozen constant object with attr_accessor
        eval("
            class TestFrozen
              attr_accessor :a
              def initialize
                @a = 1
              end
            end

            FROZEN_OBJ = TestFrozen.new.freeze

            def test = FROZEN_OBJ.a
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_OBJ)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozen@0x1010)
          PatchPoint MethodRedefined(TestFrozen@0x1010, a@0x1018, cme:0x1020)
          v28:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_multiple_ivars() {
        // Frozen object with multiple instance variables
        eval("
            class TestMultiIvars
              attr_accessor :a, :b, :c
              def initialize
                @a = 10
                @b = 20
                @c = 30
              end
            end

            MULTI_FROZEN = TestMultiIvars.new.freeze

            def test = MULTI_FROZEN.b
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:13:
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
          PatchPoint StableConstantNames(0x1000, MULTI_FROZEN)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestMultiIvars@0x1010)
          PatchPoint MethodRedefined(TestMultiIvars@0x1010, b@0x1018, cme:0x1020)
          v28:Fixnum[20] = Const Value(20)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_string_value() {
        // Frozen object with a string ivar
        eval(r#"
            class TestFrozenStr
              attr_accessor :name
              def initialize
                @name = "hello"
              end
            end

            FROZEN_STR = TestFrozenStr.new.freeze

            def test = FROZEN_STR.name
            test
            test
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_STR)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenStr@0x1010)
          PatchPoint MethodRedefined(TestFrozenStr@0x1010, name@0x1018, cme:0x1020)
          v28:StringExact[VALUE(0x1048)] = Const Value(VALUE(0x1048))
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_nil_value() {
        // Frozen object with nil ivar
        eval("
            class TestFrozenNil
              attr_accessor :value
              def initialize
                @value = nil
              end
            end

            FROZEN_NIL = TestFrozenNil.new.freeze

            def test = FROZEN_NIL.value
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_NIL)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenNil@0x1010)
          PatchPoint MethodRedefined(TestFrozenNil@0x1010, value@0x1018, cme:0x1020)
          v28:NilClass = Const Value(nil)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_no_fold_load_field_unfrozen_object() {
        // Non-frozen object should NOT be folded
        eval("
            class TestUnfrozen
              attr_accessor :a
              def initialize
                @a = 1
              end
            end

            UNFROZEN_OBJ = TestUnfrozen.new

            def test = UNFROZEN_OBJ.a
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, UNFROZEN_OBJ)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestUnfrozen@0x1010)
          PatchPoint MethodRedefined(TestUnfrozen@0x1010, a@0x1018, cme:0x1020)
          v24:CShape = LoadField v12, :shape_id@0x1048
          v25:CShape[0x1049] = GuardBitEquals v24, CShape(0x1049) recompile
          v26:BasicObject = LoadField v12, :@a@0x104a
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_with_attr_reader() {
        // Using attr_reader instead of attr_accessor
        eval("
            class TestAttrReader
              attr_reader :value
              def initialize(v)
                @value = v
              end
            end

            FROZEN_READER = TestAttrReader.new(42).freeze

            def test = FROZEN_READER.value
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_READER)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestAttrReader@0x1010)
          PatchPoint MethodRedefined(TestAttrReader@0x1010, value@0x1018, cme:0x1020)
          v28:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_symbol_value() {
        // Frozen object with a symbol ivar
        eval("
            class TestFrozenSym
              attr_accessor :sym
              def initialize
                @sym = :hello
              end
            end

            FROZEN_SYM = TestFrozenSym.new.freeze

            def test = FROZEN_SYM.sym
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_SYM)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenSym@0x1010)
          PatchPoint MethodRedefined(TestFrozenSym@0x1010, sym@0x1018, cme:0x1020)
          v28:StaticSymbol[:hello] = Const Value(VALUE(0x1048))
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_true_false() {
        // Frozen object with boolean ivars
        eval("
            class TestFrozenBool
              attr_accessor :flag
              def initialize
                @flag = true
              end
            end

            FROZEN_TRUE = TestFrozenBool.new.freeze

            def test = FROZEN_TRUE.flag
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
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
          PatchPoint StableConstantNames(0x1000, FROZEN_TRUE)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenBool@0x1010)
          PatchPoint MethodRedefined(TestFrozenBool@0x1010, flag@0x1018, cme:0x1020)
          v28:TrueClass = Const Value(true)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_no_fold_load_field_dynamic_receiver() {
        // Dynamic receiver (not a constant) should NOT be folded even if object is frozen
        eval("
            class TestDynamic
              attr_accessor :val
              def initialize
                @val = 99
              end
            end

            def test(obj) = obj.val
            o = TestDynamic.new.freeze
            test o
            test o
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :obj@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :obj@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(TestDynamic@0x1008)
          PatchPoint MethodRedefined(TestDynamic@0x1008, val@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:TestDynamic] = GuardType v10, ObjectSubclass[class_exact:TestDynamic] recompile
          v25:CShape = LoadField v23, :shape_id@0x1040
          v26:CShape[0x1041] = GuardBitEquals v25, CShape(0x1041) recompile
          v27:BasicObject = LoadField v23, :@val@0x1042
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_fold_load_field_frozen_nested_access() {
        // Accessing multiple fields from frozen constant in sequence
        eval("
            class TestNestedAccess
              attr_accessor :x, :y
              def initialize
                @x = 100
                @y = 200
              end
            end

            NESTED_FROZEN = TestNestedAccess.new.freeze

            def test = NESTED_FROZEN.x + NESTED_FROZEN.y
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:12:
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
          PatchPoint StableConstantNames(0x1000, NESTED_FROZEN)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestNestedAccess@0x1010)
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, x@0x1018, cme:0x1020)
          v49:Fixnum[100] = Const Value(100)
          PatchPoint StableConstantNames(0x1048, NESTED_FROZEN)
          v18:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, y@0x1050, cme:0x1058)
          v51:Fixnum[200] = Const Value(200)
          PatchPoint MethodRedefined(Integer@0x1080, +@0x1088, cme:0x1090)
          v52:Fixnum[300] = Const Value(300)
          CheckInterrupts
          Return v52
        ");
    }

    #[test]
    fn test_dont_fold_load_field_with_primitive_return_type() {
        eval(r#"
            S = "abc".freeze
            def test = S.bytesize
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, S)
          v12:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, bytesize@0x1018, cme:0x1020)
          v24:CInt64 = LoadField v12, :len@0x1048
          v25:Fixnum = BoxFixnum v24
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn optimize_call_to_private_method_iseq_with_fcall() {
        eval(r#"
            class C
              def callprivate = secret
              private def secret = 42
            end
            C.new.callprivate
        "#);
        assert_snapshot!(hir_string_proc("C.instance_method(:callprivate)"), @"
        fn callprivate@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, secret@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact:C] = GuardType v6, ObjectSubclass[class_exact:C] recompile
          v20:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn dont_optimize_call_to_private_method_iseq() {
        eval(r#"
            class C
              private def secret = 42
            end
            Obj = C.new
            def test = Obj.secret rescue $!
            test
        "#);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:BasicObject = Send v12, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn optimize_call_to_private_method_cfunc_with_fcall() {
        eval(r#"
            class BasicObject
              def callprivate = initialize rescue $!
            end
            Obj = BasicObject.new.callprivate
        "#);
        assert_snapshot!(hir_string_proc("BasicObject.instance_method(:callprivate)"), @"
        fn callprivate@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint NoSingletonClass(BasicObject@0x1000)
          PatchPoint MethodRedefined(BasicObject@0x1000, initialize@0x1008, cme:0x1010)
          v21:BasicObjectExact = GuardType v6, BasicObjectExact recompile
          v22:NilClass = Const Value(nil)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn dont_optimize_call_to_private_method_cfunc() {
        eval(r#"
            Obj = BasicObject.new
            def test = Obj.initialize rescue $!
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v12:BasicObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:BasicObject = Send v12, :initialize # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn dont_optimize_call_to_private_top_level_method() {
        eval(r#"
            def toplevel_method = :OK
            Obj = Object.new
            def test = Obj.toplevel_method rescue $!
            test
        "#);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v12:ObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:BasicObject = Send v12, :toplevel_method # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn optimize_call_to_protected_method_iseq_with_fcall() {
        eval(r#"
            class C
              def callprotected = secret
              protected def secret = 42
            end
            C.new.callprotected
        "#);
        assert_snapshot!(hir_string_proc("C.instance_method(:callprotected)"), @"
        fn callprotected@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, secret@0x1008, cme:0x1010)
          v19:ObjectSubclass[class_exact:C] = GuardType v6, ObjectSubclass[class_exact:C] recompile
          v20:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn dont_optimize_call_to_protected_method_iseq() {
        eval(r#"
            class C
              protected def secret = 42
            end
            Obj = C.new
            def test = Obj.secret rescue $!
            test
        "#);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v12:ObjectSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:BasicObject = Send v12, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v14
        ");
    }

    // Test that when a singleton class has been seen for a class, we skip the
    // NoSingletonClass optimization to avoid an invalidation loop.
    #[test]
    fn test_skip_optimization_after_singleton_class_seen() {
        // First, compile a function that uses the NoSingletonClass assumption
        eval(r#"
            def test(s, proc)
              s.length
              proc.call
              s.length
            end
            test("hi", -> {})
            test("hi", -> {})
        "#);
        let hir = hir_string("test");
        assert!(hir.contains("NoSingletonClass(String"), "{hir}");

        // Now we break the assumption by defining a singleton method on a string.
        eval(r#"
            special_string = +""
            test(special_string, -> { def special_string.length = -1 })
        "#);

        // The output should NOT have NoSingletonClass patchpoint for String, and should
        // fall back to SendWithoutBlock instead of the optimized CCall path.
        let hir = hir_string("test");
        assert!(! hir.contains("NoSingletonClass(String"), "{hir}");
        assert_snapshot!(hir, @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :s@0x1000
          v4:BasicObject = LoadField v2, :proc@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :s@1
          v9:BasicObject = LoadArg :proc@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          v19:BasicObject = Send v12, :length # SendFallbackReason: Singleton class previously created for receiver class
          PatchPoint NoSingletonClass(Proc@0x1008)
          PatchPoint MethodRedefined(Proc@0x1008, call@0x1010, cme:0x1018)
          v40:ObjectSubclass[class_exact:Proc] = GuardType v13, ObjectSubclass[class_exact:Proc] recompile
          v41:BasicObject = InvokeProc v40
          PatchPoint NoEPEscape(test)
          v32:BasicObject = Send v12, :length # SendFallbackReason: Singleton class previously created for receiver class
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_no_singleton_class_busts_isolated_per_iseq() {
        // First, compile a function that uses the NoSingletonClass assumption
        eval(r#"
            def will_bust(s, proc)
              s.length
              proc.call
              s.length
            end

            def call_length(s) = s.length

            will_bust("hi", -> {})
            will_bust("hi", -> {})
        "#);
        let hir = hir_string("will_bust");
        assert!(hir.contains("NoSingletonClass(String"), "{hir}");

        // Now we break the assumption by defining a singleton method on a string.
        eval(r#"
            special_string = +""
            will_bust(special_string, -> { def special_string.length = -1 })
        "#);
        let hir = hir_string("will_bust");
        assert!(! hir.contains("NoSingletonClas(String"), "{hir}");

        // But, the unrelated call_length() should still use NoSingletonClass
        eval("call_length('profile')");
        let hir = hir_string("call_length");
        assert!(hir.contains("NoSingletonClass"), "{hir}");
    }

    #[test]
    fn test_invokesuper_to_iseq_optimizes() {
        eval("
            class A
              def foo
                'A'
              end
            end

            class B < A
              def foo
                super
              end
            end

            B.new.foo; B.new.foo
        ");

        // A Ruby method as the target of `super` should optimize provided no block is given.
        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(!hir.contains("InvokeSuper "), "InvokeSuper should optimize to SendDirect but got:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:HeapBasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:HeapBasicObject):
          PatchPoint MethodRedefined(A@0x1000, foo@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          PushInlineFrame v6 (0x1050)
          v28:StringExact[VALUE(0x1058)] = Const Value(VALUE(0x1058))
          v29:StringExact = StringCopy v28
          CheckInterrupts
          PopInlineFrame
          Return v29
        ");
    }

    #[test]
    fn test_invokesuper_from_a_block() {
        _ = eval("
            define_method(:itself) { super() }
            itself
        ");

        assert_snapshot!(hir_string("itself"), @"
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
          v11:BasicObject = InvokeSuper v6, 0x1000 # SendFallbackReason: super: call from within a block
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_invokesuper_with_positional_args_optimizes() {
        eval("
            class A
              def foo(x)
                x * 2
              end
            end

            class B < A
              def foo(x)
                super(x) + 1
              end
            end

            B.new.foo(5); B.new.foo(5)
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(!hir.contains("InvokeSuper "), "InvokeSuper should optimize to SendDirect but got:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:HeapBasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:HeapBasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(A@0x1008, foo@0x1010, cme:0x1018)
          v28:CPtr = GetEP 0
          v29:RubyValue = LoadField v28, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v30:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v29, Value(VALUE(0x1048))
          v31:RubyValue = LoadField v28, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v32:FalseClass = GuardBitEquals v31, Value(false)
          PushInlineFrame v9 (0x1058), v10
          v44:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1060, *@0x1068, cme:0x1070)
          v58:Fixnum = GuardType v10, Fixnum recompile
          v59:Fixnum = FixnumMult v58, v44
          CheckInterrupts
          PopInlineFrame
          v18:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1060, +@0x1098, cme:0x10a0)
          v37:Fixnum = FixnumAdd v59, v18
          Return v37
        ");
    }

    #[test]
    fn test_invokesuper_with_forwarded_splat_args_remains_invokesuper() {
        eval("
            class A
              def foo(x)
                x * 2
              end
            end

            class B < A
              def foo(*x)
                super
              end
            end

            B.new.foo(5); B.new.foo(5)
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");
        assert!(!hir.contains("SendDirect"), "Should not optimize to SendDirect for explicit blockarg:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:ArrayExact = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:HeapBasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:HeapBasicObject, v10:BasicObject):
          v16:ArrayExact = ToArray v10
          v18:BasicObject = InvokeSuper v9, 0x1008, v16 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_invokesuper_with_block_literal_remains_invokesuper() {
        eval("
            class A
              def foo
                block_given? ? yield : 'no block'
              end
            end

            class B < A
              def foo
                super { 'from subclass' }
              end
            end

            B.new.foo; B.new.foo
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");
        assert!(!hir.contains("SendDirect"), "Should not optimize to SendDirect for block literal:\n{hir}");

        // With a block, we don't optimize to SendDirect
        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:HeapBasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:HeapBasicObject):
          v11:BasicObject = InvokeSuper v6, 0x1000 # SendFallbackReason: super: call made with a block
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_invokesuper_to_cfunc_optimizes_to_ccall() {
        eval("
            class C < Hash
              def size
                super
              end
            end

            C.new.size
        ");

        let hir = hir_string_proc("C.new.method(:size)");
        assert!(!hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");

        assert_snapshot!(hir, @"
        fn size@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:Fixnum = CCall v6, :Hash#size@0x1050
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_invokesuper_to_nonleaf_cfunc_preserves_return_type() {
        // super resolving to a non-leaf cfunc (Array#reverse: leaf but allocates,
        // so it goes through CCallWithFrame) must keep the annotated return type
        // (ArrayExact) instead of widening it to BasicObject.
        eval("
            class MyArray < Array
              def reverse
                super
              end
            end

            MyArray.new.reverse; MyArray.new.reverse
        ");

        assert_snapshot!(hir_string_proc("MyArray.instance_method(:reverse)"), @"
        fn reverse@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:ArrayExact = CCallWithFrame v6, :Array#reverse@0x1050
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_invokesuper_to_nonleaf_variadic_cfunc_preserves_return_type() {
        // super resolving to a non-leaf variadic cfunc (Array#join: StringExact)
        // must keep the annotated return type instead of widening to BasicObject.
        eval("
            class MyArray < Array
              def join(sep = nil)
                super
              end
            end

            MyArray.new([1, 2]).join(','); MyArray.new([1, 2]).join(',')
        ");

        assert_snapshot!(hir_string_proc("MyArray.instance_method(:join)"), @"
        fn join@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :sep@0x1000
          v4:CPtr = LoadPC
          v5:CPtr[CPtr(0x1001)] = Const CPtr(0x1001)
          v6:CBool = IsBitEqual v4, v5
          CondBranch v6, bb3(v1, v3), bb6()
        bb6():
          Jump bb5(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v10:BasicObject = LoadArg :self@0
          v11:NilClass = Const Value(nil)
          Jump bb3(v10, v11)
        bb3(v17:BasicObject, v18:BasicObject):
          v21:NilClass = Const Value(nil)
          Jump bb5(v17, v21)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :sep@1
          Jump bb5(v14, v15)
        bb5(v24:BasicObject, v25:BasicObject):
          PatchPoint MethodRedefined(Array@0x1008, join@0x1010, cme:0x1018)
          v38:CPtr = GetEP 0
          v39:RubyValue = LoadField v38, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v40:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v39, Value(VALUE(0x1048))
          v41:RubyValue = LoadField v38, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v42:FalseClass = GuardBitEquals v41, Value(false)
          v43:StringExact = CCallVariadic v24, :Array#join@0x1058, v25
          CheckInterrupts
          Return v43
        ");
    }

    #[test]
    fn test_invokesuper_to_nonleaf_cfunc_preserves_elidable() {
        // an elidable non-leaf cfunc reached via super (Array#reverse) whose
        // result is unused must be removed by DCE. If elidable were widened to false,
        // the dead CCallWithFrame would remain.
        eval("
            class MyArray < Array
              def reverse
                super
                self
              end
            end

            MyArray.new.reverse; MyArray.new.reverse
        ");

        assert_snapshot!(hir_string_proc("MyArray.instance_method(:reverse)"), @"
        fn reverse@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v21:CPtr = GetEP 0
          v22:RubyValue = LoadField v21, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v23:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v22, Value(VALUE(0x1040))
          v24:RubyValue = LoadField v21, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v25:FalseClass = GuardBitEquals v24, Value(false)
          CheckInterrupts
          Return v6
        ");
    }

    #[test]
    fn test_inline_invokesuper_to_basicobject_initialize() {
        eval("
            class C
              def initialize
                super
              end
            end

            C.new
        ");
        assert_snapshot!(hir_string_proc("C.instance_method(:initialize)"), @"
        fn initialize@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(BasicObject@0x1000, initialize@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_ME_CREF@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :VM_ENV_DATA_INDEX_SPECVAL@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:NilClass = Const Value(nil)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_invokesuper_to_variadic_cfunc_optimizes_to_ccall() {
        eval("
            class MyString < String
              def byteindex(needle, offset = 0)
                super(needle, offset)
              end
            end

            MyString.new('hello world').byteindex('world', 0); MyString.new('hello world').byteindex('world', 0)
        ");

        let hir = hir_string_proc("MyString.new('hello world').method(:byteindex)");
        assert!(!hir.contains("InvokeSuper "), "InvokeSuper should optimize to CCallVariadic but got:\n{hir}");
        assert!(hir.contains("CCallVariadic"), "Should optimize to CCallVariadic for variadic cfunc:\n{hir}");

        assert_snapshot!(hir, @"
        fn byteindex@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :needle@0x1000
          v4:BasicObject = LoadField v2, :offset@0x1001
          v5:CPtr = LoadPC
          v6:CPtr[CPtr(0x1002)] = Const CPtr(0x1002)
          v7:CBool = IsBitEqual v5, v6
          CondBranch v7, bb3(v1, v3, v4), bb6()
        bb6():
          Jump bb5(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v11:BasicObject = LoadArg :self@0
          v12:BasicObject = LoadArg :needle@1
          v13:NilClass = Const Value(nil)
          Jump bb3(v11, v12, v13)
        bb3(v20:BasicObject, v21:BasicObject, v22:BasicObject):
          v25:Fixnum[0] = Const Value(0)
          Jump bb5(v20, v21, v25)
        bb4():
          EntryPoint JIT(1)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :needle@1
          v18:BasicObject = LoadArg :offset@2
          Jump bb5(v16, v17, v18)
        bb5(v28:BasicObject, v29:BasicObject, v30:BasicObject):
          PatchPoint MethodRedefined(String@0x1008, byteindex@0x1010, cme:0x1018)
          v44:CPtr = GetEP 0
          v45:RubyValue = LoadField v44, :VM_ENV_DATA_INDEX_ME_CREF@0x1040
          v46:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v45, Value(VALUE(0x1048))
          v47:RubyValue = LoadField v44, :VM_ENV_DATA_INDEX_SPECVAL@0x1050
          v48:FalseClass = GuardBitEquals v47, Value(false)
          v49:BasicObject = CCallVariadic v28, :String#byteindex@0x1058, v29, v30
          CheckInterrupts
          Return v49
        ");
    }

    #[test]
    fn test_invokesuper_with_blockarg_remains_invokesuper() {
        eval("
            class A
              def foo
                block_given? ? yield : 'no block'
              end
            end

            class B < A
              def foo(&blk)
                other_block = proc { 'different block' }
                super(&other_block)
              end
            end

            B.new.foo { 'passed' }; B.new.foo { 'passed' }
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");
        assert!(!hir.contains("SendDirect"), "Should not optimize to SendDirect for explicit blockarg:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :blk@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:HeapBasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :blk@1
          v9:CPtr = GetEP 0
          StoreField v9, :blk@0x1001, v8
          v11:NilClass = Const Value(nil)
          StoreField v9, :other_block@0x1002, v11
          Jump bb3(v7, v8, v11)
        bb3(v14:HeapBasicObject, v15:BasicObject, v16:NilClass):
          PatchPoint NoSingletonClass(B@0x1008)
          PatchPoint MethodRedefined(B@0x1008, proc@0x1010, cme:0x1018)
          v42:ObjectSubclass[class_exact:B] = GuardType v14, ObjectSubclass[class_exact:B] recompile
          v43:BasicObject = CCallWithFrame v42, :Kernel#proc@0x1040, block=0x1048
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :blk@0x1001
          SetLocal :other_block, l0, EP@3, v43
          v30:CPtr = GetEP 0
          v31:BasicObject = LoadField v30, :other_block@0x1002
          v33:BasicObject = InvokeSuper v42, 0x1050, v31 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_invokesuper_with_symbol_to_proc_remains_invokesuper() {
        eval("
            class A
              def foo(items, &blk)
                items.map(&blk)
              end
            end

            class B < A
              def foo(items)
                super(items, &:succ)
              end
            end

            B.new.foo([1, 2, 3]); B.new.foo([1, 2, 3])
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");
        assert!(!hir.contains("SendDirect"), "Should not optimize to SendDirect for symbol-to-proc:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :items@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:HeapBasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :items@1
          Jump bb3(v6, v7)
        bb3(v9:HeapBasicObject, v10:BasicObject):
          v16:StaticSymbol[:succ] = Const Value(VALUE(0x1008))
          v18:BasicObject = InvokeSuper v9, 0x1010, v10, v16 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_invokesuper_with_keyword_args_remains_invokesuper() {
        eval("
          class A
            def foo(attributes = {})
              @attributes = attributes
            end
          end

          class B < A
            def foo(content = '')
              super(content: content)
            end
          end

          B.new.foo('image data'); B.new.foo('image data')
        ");

        let hir = hir_string_proc("B.new.method(:foo)");
        assert!(hir.contains("InvokeSuper "), "Expected unoptimized InvokeSuper but got:\n{hir}");

        assert_snapshot!(hir, @"
        fn foo@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :content@0x1000
          v4:CPtr = LoadPC
          v5:CPtr[CPtr(0x1001)] = Const CPtr(0x1001)
          v6:CBool = IsBitEqual v4, v5
          CondBranch v6, bb3(v1, v3), bb6()
        bb6():
          Jump bb5(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v10:HeapBasicObject = LoadArg :self@0
          v11:NilClass = Const Value(nil)
          Jump bb3(v10, v11)
        bb3(v17:HeapBasicObject, v18:BasicObject):
          v21:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v22:StringExact = StringCopy v21
          Jump bb5(v17, v22)
        bb4():
          EntryPoint JIT(1)
          v14:HeapBasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :content@1
          Jump bb5(v14, v15)
        bb5(v25:HeapBasicObject, v26:BasicObject):
          v32:BasicObject = InvokeSuper v25, 0x1010, v26 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v32
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
          CondBranch v16, bb7(), bb6(v9, v17)
        bb7():
          v19:Truthy = RefineType v10, Truthy
          CheckInterrupts
          v38:Fixnum[3] = Const Value(3)
          Return v38
        bb6(v43:BasicObject, v44:Falsy):
          v48:Fixnum[6] = Const Value(6)
          CheckInterrupts
          Return v48
        ");
    }

    #[test]
    fn specialize_polymorphic_send_iseq() {
        set_call_threshold(4);
        eval("
        class C
          def foo = 3
        end

        class D
          def foo = 4
        end

        def test o
          o.foo + 2
        end

        test C.new; test D.new; test C.new; test D.new
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:11:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:CBool = HasType v10, ObjectSubclass[class_exact:C]
          CondBranch v16, bb5(), bb6()
        bb5():
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v42:Fixnum[3] = Const Value(3)
          Jump bb4(v42)
        bb6():
          v22:CBool = HasType v10, ObjectSubclass[class_exact:D]
          CondBranch v22, bb7(), bb8()
        bb7():
          PatchPoint NoSingletonClass(D@0x1040)
          PatchPoint MethodRedefined(D@0x1040, foo@0x1010, cme:0x1048)
          v45:Fixnum[4] = Const Value(4)
          Jump bb4(v45)
        bb8():
          v28:BasicObject = Send v10, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v28)
        bb4(v15:BasicObject):
          v31:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1070, +@0x1078, cme:0x1080)
          v48:Fixnum = GuardType v15, Fixnum recompile
          v49:Fixnum = FixnumAdd v48, v31
          CheckInterrupts
          Return v49
        ");
    }

    #[test]
    fn specialize_polymorphic_send_with_immediate() {
        set_call_threshold(4);
        eval("
        class C; end

        def test o
          o.itself
        end

        test C.new; test 3; test C.new; test 4
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:5:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:CBool = HasType v10, ObjectSubclass[class_exact:C]
          CondBranch v16, bb5(), bb6()
        bb5():
          v19:ObjectSubclass[class_exact:C] = RefineType v10, ObjectSubclass[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, itself@0x1010, cme:0x1018)
          Jump bb4(v19)
        bb6():
          v22:CBool = HasType v10, Fixnum
          CondBranch v22, bb7(), bb8()
        bb7():
          v25:Fixnum = RefineType v10, Fixnum
          PatchPoint MethodRedefined(Integer@0x1040, itself@0x1010, cme:0x1018)
          Jump bb4(v25)
        bb8():
          v28:BasicObject = Send v10, :itself # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v28)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn specialize_polymorphic_send_fixnum_and_bignum() {
        // Fixnum and Bignum both have class Integer, but they should be
        // treated as different types for polymorphic dispatch because
        // Fixnum is an immediate and Bignum is a heap object.
        set_call_threshold(4);
        eval("
        def test x
          x.to_s
        end

        fixnum = 1
        bignum = 10**100
        test(fixnum)
        test(bignum)
        test(fixnum)
        test(bignum)
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
          v16:CBool = HasType v10, Fixnum
          CondBranch v16, bb5(), bb6()
        bb5():
          v19:Fixnum = RefineType v10, Fixnum
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v37:StringExact = CCallVariadic v19, :Integer#to_s@0x1040
          Jump bb4(v37)
        bb6():
          v22:CBool = HasType v10, Bignum
          CondBranch v22, bb7(), bb8()
        bb7():
          v25:Bignum = RefineType v10, Bignum
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v40:StringExact = CCallVariadic v25, :Integer#to_s@0x1040
          Jump bb4(v40)
        bb8():
          v28:BasicObject = Send v10, :to_s # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v28)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn specialize_polymorphic_send_flonum_and_heap_float() {
        set_call_threshold(4);
        eval("
        def test x
          x.to_s
        end

        flonum = 1.5
        heap_float = 1.7976931348623157e+308
        test(flonum)
        test(heap_float)
        test(flonum)
        test(heap_float)
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
          v16:CBool = HasType v10, Flonum
          CondBranch v16, bb5(), bb6()
        bb5():
          v19:Flonum = RefineType v10, Flonum
          PatchPoint MethodRedefined(Float@0x1008, to_s@0x1010, cme:0x1018)
          v37:BasicObject = CCallWithFrame v19, :Float#to_s@0x1040
          Jump bb4(v37)
        bb6():
          v22:CBool = HasType v10, HeapFloat
          CondBranch v22, bb7(), bb8()
        bb7():
          v25:HeapFloat = RefineType v10, HeapFloat
          PatchPoint MethodRedefined(Float@0x1008, to_s@0x1010, cme:0x1018)
          v40:BasicObject = CCallWithFrame v25, :Float#to_s@0x1040
          Jump bb4(v40)
        bb8():
          v28:BasicObject = Send v10, :to_s # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v28)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn specialize_polymorphic_send_static_and_dynamic_symbol() {
        set_call_threshold(4);
        eval("
        def test x
          x.to_s
        end

        static_sym = :foo
        dynamic_sym = (\"zjit_dynamic_\" + Object.new.object_id.to_s).to_sym
        test static_sym
        test dynamic_sym
        test static_sym
        test dynamic_sym
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
          v16:CBool = HasType v10, StaticSymbol
          CondBranch v16, bb5(), bb6()
        bb5():
          v19:StaticSymbol = RefineType v10, StaticSymbol
          PatchPoint MethodRedefined(Symbol@0x1008, to_s@0x1010, cme:0x1018)
          v36:StringExact = InvokeBuiltin leaf <inline_expr>, v19
          Jump bb4(v36)
        bb6():
          v22:CBool = HasType v10, DynamicSymbol
          CondBranch v22, bb7(), bb8()
        bb7():
          v25:DynamicSymbol = RefineType v10, DynamicSymbol
          PatchPoint MethodRedefined(Symbol@0x1008, to_s@0x1010, cme:0x1018)
          v38:StringExact = InvokeBuiltin leaf <inline_expr>, v25
          Jump bb4(v38)
        bb8():
          v28:BasicObject = Send v10, :to_s # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v28)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn specialize_polymorphic_send_iseq_duplicate_class_profiles() {
        set_call_threshold(4);
        eval("
        class C
          def foo = 3
        end

        O1 = C.new
        O1.instance_variable_set(:@foo, 1)
        O2 = C.new
        O2.instance_variable_set(:@bar, 2)

        def test o
          o.foo
        end

        test O1; test O2; test O1; test O2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:12:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :o@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :o@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:CBool = HasType v10, ObjectSubclass[class_exact:C]
          CondBranch v16, bb5(), bb6()
        bb5():
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          v31:Fixnum[3] = Const Value(3)
          Jump bb4(v31)
        bb6():
          v22:BasicObject = Send v10, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v22)
        bb4(v15:BasicObject):
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn upgrade_self_type_to_heap_after_setivar() {
        // Snapshot the overflow path only when this build naturally keeps five
        // ivars embedded and overflows on the next write.
        let obj = eval(r#"
            klass = Class.new do
              def initialize
                @v0 = 0
                @v1 = 1
                @v2 = 2
                @v3 = 3
                @v4 = 4
              end

              def test
                @overflow = 1
                @after = 2
              end
            end

            TEST = klass.instance_method(:test)
            OBJ = klass.new
            OBJ
        "#);
        // Skip builds where five ivars already force heap-backed storage.
        if !obj.embedded_p() {
            return;
        }

        // Make sure the next write is the one that overflows into heap-backed
        // storage, so this snapshot still exercises the self-type upgrade path.
        let probe = eval(r#"
            probe = OBJ.class.new
            probe.instance_variable_set(:@overflow, 1)
            probe
        "#);
        if probe.embedded_p() {
            return;
        }
        eval("OBJ.test");
        assert_snapshot!(hir_string_proc("TEST"), @"
        fn test@<compiled>:12:
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
          SetIvar v6, :@overflow, v10
          v14:HeapBasicObject = RefineType v6, HeapBasicObject
          v17:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          v29:CShape = LoadField v14, :shape_id@0x1000
          v30:CShape[0x1001] = GuardBitEquals v29, CShape(0x1001)
          v31:CPtr = LoadField v14, :as_heap@0x1002
          StoreField v31, :@after@0x1003, v17
          WriteBarrier v14, v17
          v34:CShape[0x1004] = Const CShape(0x1004)
          StoreField v14, :shape_id@0x1000, v34
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn recompile_after_ep_escape_uses_ep_locals() {
        // When a method creates a lambda, EP escapes to the heap. After
        // invalidation and recompilation, the compiler must use EP-based
        // locals (SetLocal/GetLocal) instead of SSA locals, because the
        // spill target (stack) and the read target (heap EP) diverge.
        eval("
            CONST = {}.freeze
            def test_ep_escape(list, sep=nil, iter_method=:each)
                sep ||= lambda { }
                kwsplat = CONST
                list.__send__(iter_method) {|*v| yield(*v) }
            end

            test_ep_escape({a: 1}, nil, :each_pair) { |k, v|
                test_ep_escape([1], lambda { }) { |x| }
            }
            test_ep_escape({a: 1}, nil, :each_pair) { |k, v|
                test_ep_escape([1], lambda { }) { |x| }
            }
        ");
        assert_snapshot!(hir_string("test_ep_escape"), @"
        fn test_ep_escape@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :list@0x1000
          v4:BasicObject = LoadField v2, :sep@0x1001
          v5:BasicObject = LoadField v2, :iter_method@0x1002
          v6:NilClass = Const Value(nil)
          v7:CPtr = LoadPC
          v8:CPtr[CPtr(0x1003)] = Const CPtr(0x1003)
          v9:CBool = IsBitEqual v7, v8
          CondBranch v9, bb3(v1, v3, v4, v5, v6), bb9()
        bb9():
          v11:CPtr[CPtr(0x1004)] = Const CPtr(0x1004)
          v12:CBool = IsBitEqual v7, v11
          CondBranch v12, bb5(v1, v3, v4, v5, v6), bb10()
        bb10():
          Jump bb7(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :list@1
          v18:CPtr = GetEP 0
          StoreField v18, :list@0x1001, v17
          v20:NilClass = Const Value(nil)
          StoreField v18, :sep@0x1002, v20
          v22:NilClass = Const Value(nil)
          StoreField v18, :iter_method@0x1005, v22
          v24:NilClass = Const Value(nil)
          StoreField v18, :kwsplat@0x1006, v24
          Jump bb3(v16, v17, v20, v22, v24)
        bb3(v51:BasicObject, v52:BasicObject, v53:BasicObject, v54:BasicObject, v55:NilClass):
          v58:NilClass = Const Value(nil)
          SetLocal :sep, l0, EP@5, v58
          Jump bb5(v51, v52, v58, v54, v55)
        bb4():
          EntryPoint JIT(1)
          v28:BasicObject = LoadArg :self@0
          v29:BasicObject = LoadArg :list@1
          v30:CPtr = GetEP 0
          StoreField v30, :list@0x1001, v29
          v32:BasicObject = LoadArg :sep@2
          StoreField v30, :sep@0x1002, v32
          v34:NilClass = Const Value(nil)
          StoreField v30, :iter_method@0x1005, v34
          v36:NilClass = Const Value(nil)
          StoreField v30, :kwsplat@0x1006, v36
          Jump bb5(v28, v29, v32, v34, v36)
        bb5(v62:BasicObject, v63:BasicObject, v64:BasicObject, v65:BasicObject, v66:NilClass):
          v69:StaticSymbol[:each] = Const Value(VALUE(0x1008))
          SetLocal :iter_method, l0, EP@4, v69
          Jump bb7(v62, v63, v64, v69, v66)
        bb6():
          EntryPoint JIT(2)
          v40:BasicObject = LoadArg :self@0
          v41:BasicObject = LoadArg :list@1
          v42:CPtr = GetEP 0
          StoreField v42, :list@0x1001, v41
          v44:BasicObject = LoadArg :sep@2
          StoreField v42, :sep@0x1002, v44
          v46:BasicObject = LoadArg :iter_method@3
          StoreField v42, :iter_method@0x1005, v46
          v48:NilClass = Const Value(nil)
          StoreField v42, :kwsplat@0x1006, v48
          Jump bb7(v40, v41, v44, v46, v48)
        bb7(v73:BasicObject, v74:BasicObject, v75:BasicObject, v76:BasicObject, v77:NilClass):
          CheckInterrupts
          v83:CBool = Test v75
          v84:Truthy = RefineType v75, Truthy
          CondBranch v83, bb8(v73, v74, v84, v76, v77), bb11()
        bb11():
          v86:Falsy = RefineType v75, Falsy
          PatchPoint MethodRedefined(Object@0x1010, lambda@0x1018, cme:0x1020)
          v132:ObjectSubclass[class_exact*:Object@VALUE(0x1010)] = GuardType v73, ObjectSubclass[class_exact*:Object@VALUE(0x1010)] recompile
          v133:BasicObject = CCallWithFrame v132, :Kernel#lambda@0x1048, block=0x1050
          v90:CPtr = GetEP 0
          v91:BasicObject = LoadField v90, :list@0x1001
          v93:BasicObject = LoadField v90, :iter_method@0x1005
          v94:BasicObject = LoadField v90, :kwsplat@0x1006
          SetLocal :sep, l0, EP@5, v133
          Jump bb8(v132, v91, v133, v93, v94)
        bb8(v98:BasicObject, v99:BasicObject, v100:BasicObject, v101:BasicObject, v102:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1058, CONST)
          v108:HashExact[VALUE(0x1060)] = Const Value(VALUE(0x1060))
          SetLocal :kwsplat, l0, EP@3, v108
          v113:CPtr = GetEP 0
          v114:BasicObject = LoadField v113, :list@0x1001
          v116:CPtr = GetEP 0
          v117:BasicObject = LoadField v116, :iter_method@0x1005
          v119:BasicObject = Send v114, 0x1068, :__send__, v117 # SendFallbackReason: Send: unsupported method type Optimized
          v120:CPtr = GetEP 0
          v121:BasicObject = LoadField v120, :list@0x1001
          v122:BasicObject = LoadField v120, :sep@0x1002
          v123:BasicObject = LoadField v120, :iter_method@0x1005
          v124:BasicObject = LoadField v120, :kwsplat@0x1006
          CheckInterrupts
          Return v119
        ");
    }

    #[test]
    fn test_array_each() {
        eval("[1, 2, 3].each { |x| x }");
        assert_snapshot!(hir_string_proc("Array.instance_method(:each)"), @"
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
          CondBranch v17, bb9(), bb4(v8, v9)
        bb9():
          v35:Fixnum[0] = Const Value(0)
          Jump bb8(v8, v35)
        bb8(v48:BasicObject, v49:Fixnum):
          v52:Array = RefineType v48, Array
          v53:CInt64 = ArrayLength v52
          v54:Fixnum = BoxFixnum v53
          v55:BoolExact = FixnumGe v49, v54
          v57:CBool = Test v55
          CondBranch v57, bb11(), bb7(v48, v49)
        bb11():
          CheckInterrupts
          Return v48
        bb7(v70:BasicObject, v71:Fixnum):
          v75:Array = RefineType v70, Array
          v76:CInt64 = UnboxFixnum v71
          v77:BasicObject = ArrayAref v75, v76
          v79:BasicObject = InvokeBlock v77 # SendFallbackReason: InvokeBlock: not yet specialized
          v83:Fixnum[1] = Const Value(1)
          v84:Fixnum = FixnumAdd v71, v83
          PatchPoint NoEPEscape(each)
          Jump bb8(v70, v84)
        bb4(v23:BasicObject, v24:NilClass):
          v28:BasicObject = InvokeBuiltin <inline_expr>, v23
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_delete_duplicate_store() {
        eval("
            class C
              def initialize
                a = 1
                @a = a
                @a = a
              end
            end

            C.new
        ");
        assert_snapshot!(hir_string_proc("C.instance_method(:initialize)"), @"
        fn initialize@<compiled>:4:
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
          PatchPoint SingleRactorMode
          v19:HeapBasicObject = GuardType v8, HeapBasicObject
          v20:CShape = LoadField v19, :shape_id@0x1000
          v21:CShape[0x1001] = GuardBitEquals v20, CShape(0x1001) recompile
          StoreField v19, :@a@0x1002, v13
          WriteBarrier v19, v13
          v24:CShape[0x1003] = Const CShape(0x1003)
          StoreField v19, :shape_id@0x1000, v24
          PatchPoint NoEPEscape(initialize)
          PatchPoint SingleRactorMode
          WriteBarrier v19, v13
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_remove_duplicate_store_with_non_effectful_insns_between() {
        eval("
            class C
              def initialize
                a = 1
                @a = a
                b = 5
                b += a
                @a = a
              end
            end

            C.new
        ");
        assert_snapshot!(hir_string_proc("C.instance_method(:initialize)"), @"
        fn initialize@<compiled>:4:
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
          v16:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          v22:HeapBasicObject = GuardType v10, HeapBasicObject
          v23:CShape = LoadField v22, :shape_id@0x1000
          v24:CShape[0x1001] = GuardBitEquals v23, CShape(0x1001) recompile
          StoreField v22, :@a@0x1002, v16
          WriteBarrier v22, v16
          v27:CShape[0x1003] = Const CShape(0x1003)
          StoreField v22, :shape_id@0x1000, v27
          v32:Fixnum[5] = Const Value(5)
          PatchPoint NoEPEscape(initialize)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v63:Fixnum[6] = Const Value(6)
          PatchPoint SingleRactorMode
          WriteBarrier v22, v16
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_remove_two_stores() {
        eval("
            class C
              def initialize
                a = 1
                @a = a
                @a = a
                @a = a
              end
            end

            C.new
        ");
        assert_snapshot!(hir_string_proc("C.instance_method(:initialize)"), @"
        fn initialize@<compiled>:4:
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
          PatchPoint SingleRactorMode
          v19:HeapBasicObject = GuardType v8, HeapBasicObject
          v20:CShape = LoadField v19, :shape_id@0x1000
          v21:CShape[0x1001] = GuardBitEquals v20, CShape(0x1001) recompile
          StoreField v19, :@a@0x1002, v13
          WriteBarrier v19, v13
          v24:CShape[0x1003] = Const CShape(0x1003)
          StoreField v19, :shape_id@0x1000, v24
          PatchPoint NoEPEscape(initialize)
          PatchPoint SingleRactorMode
          WriteBarrier v19, v13
          WriteBarrier v19, v13
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_exit_from_function_stub_for_opt_keyword_callee() {
        // We have a SendDirect to a callee that fails to compile,
        // so the function stub has to take care of exiting to
        // interpreter.
        eval("
            def target(a = binding.local_variable_get(:a), b: nil)
              ::RubyVM::ZJIT.induce_compile_failure!
              [a, b]
            end

            def entry = target(b: -1)

            raise 'wrong' unless [nil, -1] == entry
            raise 'wrong' unless [nil, -1] == entry
        ");

        crate::hir::tests::hir_build_tests::assert_compile_fails("target", ParseError::DirectiveInduced);
        let hir = hir_string("entry");
        assert!(hir.contains("SendDirect"), "{hir}");
    }

    #[test]
    fn test_exit_from_function_stub_for_lead_opt() {
        // We have a SendDirect to a callee that fails to compile,
        // so the function stub has to take care of exiting to
        // interpreter.
        let result = eval("
            def target(_required, a = a, b = b)
              ::RubyVM::ZJIT.induce_compile_failure!
              a
            end

            def entry = target(1)

            entry
            entry
        ");
        assert_eq!(Qnil, result);

        crate::hir::tests::hir_build_tests::assert_compile_fails("target", ParseError::DirectiveInduced);
        let hir = hir_string("entry");
        assert!(hir.contains("SendDirect"), "{hir}");
    }

    #[test]
    fn test_recompile_no_profile_send() {
        // Test the SideExit -> recompile flow: a no-profile send becomes a SideExit,
        // the exit profiles the send, triggers recompilation, and the new version
        // optimizes it to SendDirect.
        eval("
            def greet_recompile(x) = x.to_s
            def test_no_profile_recompile(flag)
              if flag
                greet_recompile(42)
              else
                'hello'
              end
            end
        ");

        // With call_threshold=2, num_profiles=1:
        //   1st call profiles (flag=false, so greet is never reached)
        //   2nd call compiles (greet has no profile data -> SideExit recompile)
        eval("test_no_profile_recompile(false); test_no_profile_recompile(false)");

        // Now call with flag=true. This hits the SideExit, which profiles
        // the send and invalidates the ISEQ for recompilation.
        eval("test_no_profile_recompile(true)");

        // After profiling via the side exit, rebuilding HIR should now
        // have a SendDirect for greet_recompile instead of SideExit.
        assert_snapshot!(hir_string("test_no_profile_recompile"), @"
        fn test_no_profile_recompile@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :flag@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :flag@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          CondBranch v16, bb5(), bb4(v9, v17)
        bb5():
          v19:Truthy = RefineType v10, Truthy
          v23:Fixnum[42] = Const Value(42)
          PatchPoint MethodRedefined(Object@0x1008, greet_recompile@0x1010, cme:0x1018)
          v43:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v43 (0x1040), v23
          PatchPoint MethodRedefined(Integer@0x1048, to_s@0x1050, cme:0x1058)
          v63:StringExact = CCallVariadic v23, :Integer#to_s@0x1080
          CheckInterrupts
          PopInlineFrame
          Return v63
        bb4(v30:BasicObject, v31:Falsy):
          v35:StringExact[VALUE(0x1088)] = Const Value(VALUE(0x1088))
          v36:StringExact = StringCopy v35
          CheckInterrupts
          Return v36
        ");
    }

    #[test]
    fn test_recompile_no_profile_send_with_blockarg() {
        // Test that no-profile send recompilation profiles explicit blockargs.
        // The call remains a Send fallback because &block is still complex, but
        // it should no longer be a NoProfileSend side exit after recompilation.
        eval("
            def passthrough_recompile_blockarg(x, &block)
              block.call(x)
            end

            def test(flag, block)
              if flag
                passthrough_recompile_blockarg(42, &block)
              else
                'hello'
              end
            end
        ");

        // With call_threshold=2, num_profiles=1, the send is not profiled
        // during initial profiling because flag=false skips that branch.
        eval("
            block = proc { |x| x }
            test(false, block)
            test(false, block)
        ");

        // This hits the NoProfileSend side exit, profiles the send including
        // its explicit blockarg, and invalidates the ISEQ for recompilation.
        eval("
            block = proc { |x| x }
            test(true, block)
        ");

        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :flag@0x1000
          v4:BasicObject = LoadField v2, :block@0x1001
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :flag@1
          v9:BasicObject = LoadArg :block@2
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:BasicObject):
          CheckInterrupts
          v19:CBool = Test v12
          v20:Falsy = RefineType v12, Falsy
          CondBranch v19, bb5(), bb4(v11, v20, v13)
        bb5():
          v22:Truthy = RefineType v12, Truthy
          v26:Fixnum[42] = Const Value(42)
          v29:BasicObject = Send v11, &block, :passthrough_recompile_blockarg, v26, v13 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          Return v29
        bb4(v34:BasicObject, v35:Falsy, v36:BasicObject):
          v40:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v41:StringExact = StringCopy v40
          CheckInterrupts
          Return v41
        ");
    }

    #[test]
    fn test_no_profile_send_on_final_version() {
        // On the final ISEQ version (MAX_ISEQ_VERSIONS reached), no-profile sends should
        // remain as Send fallbacks instead of being converted to SideExits, since recompilation
        // is no longer possible and SideExits would fire every time without benefit.
        //
        // Use call_threshold=3 to ensure the method is auto-compiled before hir_string() builds
        // the HIR. The auto-compile creates version 1, and hir_string() creates version 2
        // (= MAX_ISEQ_VERSIONS), so this is the final version.
        set_call_threshold(3);
        set_max_versions(2);
        set_inline_threshold(0);

        eval("
            def greet_final(x) = x.to_s
            def test_final_version(flag)
              if flag
                greet_final(42)
              else
                'hello'
              end
            end
        ");
        // Call enough times to trigger auto-compilation. flag=false so greet_final is never
        // reached and has no profile data.
        eval("3.times { test_final_version(false) }");

        // On the final version, greet_final should be a Send fallback, not a SideExit.
        assert_snapshot!(hir_string("test_final_version"), @"
        fn test_final_version@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :flag@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :flag@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          CheckInterrupts
          v16:CBool = Test v10
          v17:Falsy = RefineType v10, Falsy
          CondBranch v16, bb5(), bb4(v9, v17)
        bb5():
          v19:Truthy = RefineType v10, Truthy
          v23:Fixnum[42] = Const Value(42)
          v25:BasicObject = Send v9, :greet_final, v23 # SendFallbackReason: SendWithoutBlock: no profile data available
          CheckInterrupts
          Return v25
        bb4(v30:BasicObject, v31:Falsy):
          v35:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v36:StringExact = StringCopy v35
          CheckInterrupts
          Return v36
        ");
    }

    #[test]
    fn test_invokeblock_ifunc() {
        eval("
            class IFuncTestList
              include Enumerable
              def each
                yield 1
                yield 2
              end
            end
            IFuncTestList.new.map { |x| x }
        ");
        assert_snapshot!(hir_string_proc("IFuncTestList.instance_method(:each)"), @"
        fn each@<compiled>:5:
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
          v12:CPtr = GetEP 0
          v13:CInt64 = LoadField v12, :VM_ENV_DATA_INDEX_SPECVAL@0x1000
          v14:CInt64[3] = Const CInt64(3)
          v15:CInt64 = IntAnd v13, v14
          v16:CInt64[3] = Const CInt64(3)
          v17:CBool = IsBitEqual v15, v16
          CondBranch v17, bb5(), bb6()
        bb5():
          v20:BasicObject = InvokeBlockIfunc v13, v10
          Jump bb4(v20)
        bb6():
          v22:BasicObject = InvokeBlock v10 # SendFallbackReason: InvokeBlock: not yet specialized
          Jump bb4(v22)
        bb4(v18:BasicObject):
          v27:Fixnum[2] = Const Value(2)
          v29:CPtr = GetEP 0
          v30:CInt64 = LoadField v29, :VM_ENV_DATA_INDEX_SPECVAL@0x1000
          v31:CInt64[3] = Const CInt64(3)
          v32:CInt64 = IntAnd v30, v31
          v33:CInt64[3] = Const CInt64(3)
          v34:CBool = IsBitEqual v32, v33
          CondBranch v34, bb8(), bb9()
        bb8():
          v37:BasicObject = InvokeBlockIfunc v30, v27
          Jump bb7(v37)
        bb9():
          v39:BasicObject = InvokeBlock v27 # SendFallbackReason: InvokeBlock: not yet specialized
          Jump bb7(v39)
        bb7(v35:BasicObject):
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_dedup_guard_type() {
        // Two subtractions on the same Fixnum operand `n` each require a
        // GuardType n, Fixnum.  The second guard is redundant and should be
        // eliminated by fold_constants.
        eval("
            def test(n)
              (n - 1) + (n - 2)
            end
            test 1; test 2
        ");
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, -@0x1010, cme:0x1018)
          v35:Fixnum = GuardType v10, Fixnum recompile
          v36:Fixnum = FixnumSub v35, v15
          v21:Fixnum[2] = Const Value(2)
          v40:Fixnum = FixnumSub v35, v21
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1040, cme:0x1048)
          v44:Fixnum = FixnumAdd v36, v40
          CheckInterrupts
          Return v44
        ");
    }

    #[test]
    fn test_dedup_guard_type_across_cfg_join() {
        eval("
            def test(n, cond)
              if cond
                a = n + 1
              else
                a = n + 2
              end
              n + a
            end
            test(1, true); test(1, false)
        ");
        let hir = hir_string("test");
        let guard_count = hir.matches("GuardType").count();
        assert_eq!(
            guard_count, 2,
            "expected 2 GuardType instructions after cross-block dedup, found {guard_count}\n\nHIR:\n{hir}"
        );
    }

    #[test]
    fn test_forward_guard_through_conditional_branch() {
        eval("
            def test(n, a, b)
              if a
                if b
                  n + 1
                else
                  n + 2
                end
              else
                n + 3
              end
            end
            test(1, true, true); test(1, true, false); test(1, false, false)
        ");
        let hir = hir_string("test");
        let guard_count = hir.matches("GuardType").count();
        assert!(
            guard_count <= 3,
            "expected at most 3 GuardType instructions (one per leaf branch) after forwarding through conditional branches, found {guard_count}\n\nHIR:\n{hir}"
        );
    }

    #[test]
    fn test_no_forward_when_no_guard_in_branches() {
        let src = "
            def test(n, cond)
              a = if cond then 1 else 2 end
              n + a
            end
            test(1, true); test(1, false)
        ";
        eval(src);
        let hir = hir_string("test");
        let guard_count = hir.matches("GuardType").count();
        assert_eq!(
            guard_count, 1,
            "expected 1 GuardType (merge block only), found {guard_count}\n\nHIR:\n{hir}"
        );
    }

    #[test]
    fn test_infer_types_across_non_maximal_basic_blocks() {
        // Previous worklist-based type inference only worked for maximal SSA. This is a regression
        // test for hanging.
        eval("
            class TheClass
              def set_value_loop
                i = 0
                while i < 10
                  @levar ||= i
                  i += 1
                end
              end
            end
            3.times do |i|
              TheClass.new.set_value_loop
            end
        ");
        assert_snapshot!(hir_string_proc("TheClass.instance_method(:set_value_loop)"), @"
        fn set_value_loop@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb3(v1, v2)
        bb2():
          EntryPoint JIT(0)
          v5:HeapBasicObject = LoadArg :self@0
          v6:NilClass = Const Value(nil)
          Jump bb3(v5, v6)
        bb3(v8:HeapBasicObject, v9:NilClass):
          v13:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Jump bb6(v8, v13)
        bb6(v19:HeapBasicObject, v20:Fixnum):
          v24:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v100:BoolExact = FixnumLt v20, v24
          CheckInterrupts
          v30:CBool = Test v100
          CondBranch v30, bb4(v19, v20), bb7()
        bb4(v40:HeapBasicObject, v41:Fixnum):
          PatchPoint SingleRactorMode
          v48:CShape = LoadField v40, :shape_id@0x1038
          v49:CShape[0x1039] = Const CShape(0x1039)
          v50:CBool = IsBitEqual v48, v49
          CondBranch v50, bb9(), bb10()
        bb9():
          v52:BasicObject = LoadField v40, :@levar@0x103a
          Jump bb8(v52)
        bb10():
          v54:CShape = LoadField v40, :shape_id@0x1038
          v55:CShape[0x103b] = Const CShape(0x103b)
          v56:CBool = IsBitEqual v54, v55
          CondBranch v56, bb11(), bb12()
        bb11():
          v58:NilClass = Const Value(nil)
          Jump bb8(v58)
        bb12():
          v60:BasicObject = GetIvar v40, :@levar
          Jump bb8(v60)
        bb8(v47:BasicObject):
          CheckInterrupts
          v64:CBool = Test v47
          CondBranch v64, bb5(v40, v41), bb13()
        bb13():
          PatchPoint NoEPEscape(set_value_loop)
          PatchPoint SingleRactorMode
          v74:CShape = LoadField v40, :shape_id@0x1038
          v75:CShape[0x103b] = GuardBitEquals v74, CShape(0x103b) recompile
          StoreField v40, :@levar@0x103a, v41
          WriteBarrier v40, v41
          v78:CShape[0x1039] = Const CShape(0x1039)
          StoreField v40, :shape_id@0x1038, v78
          Jump bb5(v40, v41)
        bb5(v82:HeapBasicObject, v83:Fixnum):
          PatchPoint NoEPEscape(set_value_loop)
          v90:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x103c, cme:0x1040)
          v104:Fixnum = FixnumAdd v83, v90
          Jump bb6(v82, v104)
        bb7():
          v35:NilClass = Const Value(nil)
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_float_nan_p_annotation() {
        eval(r#"
            def test(x) = x.nan?
            test(1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, nan?@0x1010, cme:0x1018)
          v23:Flonum = GuardType v10, Flonum recompile
          v24:BoolExact = CCall v23, :Float#nan?@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_float_finite_p_annotation() {
        eval(r#"
            def test(x) = x.finite?
            test(1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, finite?@0x1010, cme:0x1018)
          v23:Flonum = GuardType v10, Flonum recompile
          v24:BoolExact = CCall v23, :Float#finite?@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_float_infinite_p_annotation() {
        eval(r#"
            def test(x) = x.infinite?
            test(1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, infinite?@0x1010, cme:0x1018)
          v23:Flonum = GuardType v10, Flonum recompile
          v24:NilClass|Fixnum = CCall v23, :Float#infinite?@0x1040
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_integer_even_p_annotation() {
        eval(r#"
            def test(x) = x.even?
            test(2)
        "#);
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
          PatchPoint MethodRedefined(Integer@0x1008, even?@0x1010, cme:0x1018)
          v22:Fixnum = GuardType v10, Fixnum recompile
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v22
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_integer_odd_p_annotation() {
        eval(r#"
            def test(x) = x.odd?
            test(3)
        "#);
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
          PatchPoint MethodRedefined(Integer@0x1008, odd?@0x1010, cme:0x1018)
          v22:Fixnum = GuardType v10, Fixnum recompile
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v22
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_float_zero_p_annotation() {
        eval(r#"
            def test(x) = x.zero?
            test(1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, zero?@0x1010, cme:0x1018)
          v22:Flonum = GuardType v10, Flonum recompile
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v22
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_float_positive_p_annotation() {
        eval(r#"
            def test(x) = x.positive?
            test(1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, positive?@0x1010, cme:0x1018)
          v22:Flonum = GuardType v10, Flonum recompile
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v22
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_float_negative_p_annotation() {
        eval(r#"
            def test(x) = x.negative?
            test(-1.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, negative?@0x1010, cme:0x1018)
          v22:Flonum = GuardType v10, Flonum recompile
          v23:BoolExact = InvokeBuiltin leaf <inline_expr>, v22
          CheckInterrupts
          Return v23
        ");
    }
    #[test]
    fn test_float_add_inline() {
        eval(r#"
            def test(a, b) = a + b
            test(1.0, 2.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, +@0x1010, cme:0x1018)
          v28:Flonum = GuardType v12, Flonum recompile
          v29:Flonum = GuardType v13, Flonum
          v30:Float = FloatAdd v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_float_mul_inline() {
        eval(r#"
            def test(a, b) = a * b
            test(1.5, 2.5)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, *@0x1010, cme:0x1018)
          v28:Flonum = GuardType v12, Flonum recompile
          v29:Flonum = GuardType v13, Flonum
          v30:Float = FloatMul v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_float_sub_inline() {
        eval(r#"
            def test(a, b) = a - b
            test(5.0, 3.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, -@0x1010, cme:0x1018)
          v28:Flonum = GuardType v12, Flonum recompile
          v29:Flonum = GuardType v13, Flonum
          v30:Float = FloatSub v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_float_div_inline() {
        eval(r#"
            def test(a, b) = a / b
            test(10.0, 3.0)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, /@0x1010, cme:0x1018)
          v28:Flonum = GuardType v12, Flonum recompile
          v29:Flonum = GuardType v13, Flonum
          v30:Float = FloatDiv v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_float_to_i_inline() {
        eval(r#"
            def test(a) = a.to_i
            test(3.7)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, to_i@0x1010, cme:0x1018)
          v23:Flonum = GuardType v10, Flonum recompile
          v24:Integer = FloatToInt v23
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_float_mul_fixnum_inline() {
        eval(r#"
            def test(a, b) = a * b
            test(1.5, 3)
        "#);
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
          PatchPoint MethodRedefined(Float@0x1008, *@0x1010, cme:0x1018)
          v28:Flonum = GuardType v12, Flonum recompile
          v29:Fixnum = GuardType v13, Fixnum
          v30:Float = FloatMul v28, v29
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_elide_repeated_heap_object_guards() {
        eval(r#"
            C = Struct.new(:var)
            def test(obj)
              sum = 0
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum += obj.var
              sum
            end
            test(C.new(3))
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :obj@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :obj@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          v17:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, var@0x1010, cme:0x1018)
          v138:ObjectSubclass[class_exact:C] = GuardType v12, ObjectSubclass[class_exact:C] recompile
          v139:BasicObject = LoadField v138, :var@0x1040
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v143:Fixnum = GuardType v139, Fixnum
          PatchPoint NoEPEscape(test)
          v153:Fixnum = FixnumAdd v143, v143
          v162:Fixnum = FixnumAdd v153, v143
          v171:Fixnum = FixnumAdd v162, v143
          v180:Fixnum = FixnumAdd v171, v143
          v189:Fixnum = FixnumAdd v180, v143
          v198:Fixnum = FixnumAdd v189, v143
          v207:Fixnum = FixnumAdd v198, v143
          v216:Fixnum = FixnumAdd v207, v143
          v225:Fixnum = FixnumAdd v216, v143
          CheckInterrupts
          Return v225
        ");
    }

    #[test]
    fn test_dont_fold_array_length() {
        eval(r#"
            A = [1, 2, 3, 4]
            def test = A.length
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, A)
          v12:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, length@0x1018, cme:0x1020)
          v25:CInt64 = ArrayLength v12
          v26:Fixnum = BoxFixnum v25
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_fold_frozen_array_length() {
        eval(r#"
            A = [1, 2, 3, 4].freeze
            def test = A.length
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, A)
          v12:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, length@0x1018, cme:0x1020)
          v27:CInt64[4] = Const CInt64(4)
          v26:Fixnum = BoxFixnum v27
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_elide_test_of_box_bool() {
        eval(r#"
            def test(a, b)
              if a == b
                3
              else
                4
              end
            end
            test(:a, :b)
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
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
          PatchPoint MethodRedefined(Symbol@0x1008, ==@0x1010, cme:0x1018)
          v48:StaticSymbol = GuardType v12, StaticSymbol recompile
          v49:CBool = IsBitEqual v48, v13
          v50:BoolExact = BoxBool v49
          CheckInterrupts
          CondBranch v49, bb5(), bb4(v11, v48, v13)
        bb5():
          v29:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v29
        bb4(v34:BasicObject, v35:StaticSymbol, v36:BasicObject):
          v40:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v40
        ");
    }

    #[test]
    fn test_trigger_guard_type_recompilation() {
        set_max_versions(2);
        set_inline_threshold(0);
        eval("
            class C
              def f(x)
                @a = 1
                y = x + 1
                @a = y
              end
            end

            # As of 06/04/2026, zjit/src/options.rs uses 5 as the default number of profiles
            # Let's pick a number that is reasonably larger to ensure compilation, even if
            # the default value changes a bit
            num_to_compile = 30

            c = C.new

            # Repeatedly call an integer until this fast path gets JITed
            num_to_compile.times { c.f(1) }

        ");

        let intermediate_hir = hir_string_proc("C.new.method(:f)");

        eval("
            # Supposed to be the same as the earlier Ruby method in this test
            num_to_compile = 30
            c = C.new
            # Call this with a float in order to trigger a guard failure
            # Do this enough times to cause a recompilation
            num_to_compile.times { c.f(1.5) }
        ");
        let final_hir = hir_string_proc("C.new.method(:f)");

        assert_snapshot!(format!("{intermediate_hir}\n{final_hir}"), @"
        fn f@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:HeapBasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:HeapBasicObject, v12:BasicObject, v13:NilClass):
          v17:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          SetIvar v11, :@a, v17
          PatchPoint NoEPEscape(f)
          v27:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1010, cme:0x1018)
          v46:Fixnum = GuardType v12, Fixnum recompile
          v47:Fixnum = FixnumAdd v46, v27
          PatchPoint SingleRactorMode
          SetIvar v11, :@a, v47
          CheckInterrupts
          Return v47

        fn f@<compiled>:4:
        bb1():
          EntryPoint interpreter
          v1:HeapBasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :x@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:HeapBasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :x@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:HeapBasicObject, v12:BasicObject, v13:NilClass):
          v17:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          SetIvar v11, :@a, v17
          PatchPoint NoEPEscape(f)
          v27:Fixnum[1] = Const Value(1)
          v31:CBool = HasType v12, Flonum
          CondBranch v31, bb5(), bb6()
        bb5():
          v34:Flonum = RefineType v12, Flonum
          PatchPoint MethodRedefined(Float@0x1008, +@0x1010, cme:0x1018)
          v60:Float = FloatAdd v34, v27
          Jump bb4(v60)
        bb6():
          v37:CBool = HasType v12, Fixnum
          CondBranch v37, bb7(), bb8()
        bb7():
          v40:Fixnum = RefineType v12, Fixnum
          PatchPoint MethodRedefined(Integer@0x1040, +@0x1010, cme:0x1048)
          v63:Fixnum = FixnumAdd v40, v27
          Jump bb4(v63)
        bb8():
          PatchPoint MethodRedefined(Float@0x1008, +@0x1010, cme:0x1018)
          v66:Flonum = GuardType v12, Flonum recompile
          v67:Float = FloatAdd v66, v27
          Jump bb4(v67)
        bb4(v30:Float|Fixnum):
          PatchPoint SingleRactorMode
          SetIvar v11, :@a, v30
          CheckInterrupts
          Return v30
        ");
    }

    // Helper that compiles with inlining enabled. Temporarily sets the inline
    // threshold, compiles and optimizes, then restores the original value.
    #[track_caller]
    fn hir_string_with_inlining(method: &str) -> String {
        let old_threshold = get_option!(inline_threshold);
        unsafe { OPTIONS.as_mut().unwrap().inline_threshold = 30; }
        let result = hir_string(method);
        unsafe { OPTIONS.as_mut().unwrap().inline_threshold = old_threshold; }
        result
    }

    #[test]
    fn test_inline_method_with_send() {
        // The callee-internal `x + x` Send gets specialized to FixnumAdd because the callee's
        // profile entries are merged into the caller's ProfileOracle during inlining.
        eval("
            def double(x)
              x + x
            end
            def test(n)
              double(n)
            end
            test(1)
            test(1)
        ");
        assert_snapshot!(hir_string_with_inlining("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, double@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v44:Fixnum = GuardType v10, Fixnum recompile
          v46:Fixnum = FixnumAdd v44, v44
          CheckInterrupts
          PopInlineFrame
          Return v46
        ");
    }

    #[test]
    fn test_inline_method_with_multiple_returns() {
        // `clamp_nonneg` has two Return instructions (one from the early `return 0 if ...`,
        // one from the implicit trailing `x`). Inlining rewrites each Return to a Jump into
        // the continuation block, whose single Param merges the return values.
        eval("
            def clamp_nonneg(x)
              return 0 if x < 0
              x
            end
            def test(n)
              clamp_nonneg(n)
            end
            test(1)
            test(1)
        ");
        assert_snapshot!(hir_string_with_inlining("test"), @"
        fn test@<compiled>:7:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, clamp_nonneg@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          v31:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1048, <@0x1050, cme:0x1058)
          v62:Fixnum = GuardType v10, Fixnum recompile
          v63:BoolExact = FixnumLt v62, v31
          CheckInterrupts
          v37:CBool = Test v63
          CondBranch v37, bb7(), bb6(v23, v62)
        bb7():
          v42:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Jump bb4(v42)
        bb6(v47:ObjectSubclass[class_exact*:Object@VALUE(0x1008)], v48:Fixnum):
          CheckInterrupts
          Jump bb4(v48)
        bb4(v56:Fixnum):
          PopInlineFrame
          CheckInterrupts
          Return v56
        ");
    }

    #[test]
    fn test_inline_arithmetic_method() {
        eval("
            def add_one(x)
              x + 1
            end
            def test(n)
              add_one(n)
            end
            test(1)
            test(1)
        ");
        assert_snapshot!(hir_string_with_inlining("test"), @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, add_one@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          v31:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v45:Fixnum = GuardType v10, Fixnum recompile
          v46:Fixnum = FixnumAdd v45, v31
          CheckInterrupts
          PopInlineFrame
          Return v46
        ");
    }

    #[test]
    fn test_final_inline_iteration_specializes_inlined_iseq_send() {
        eval("
            def inner(x)
              x + 1
            end
            def outer(x)
              inner(x)
            end
            def test(n)
              outer(n)
            end
            test(1)
            test(1)
        ");

        let old_threshold = get_option!(inline_threshold);
        let old_max_iterations = get_option!(inline_max_iterations);
        unsafe {
            OPTIONS.as_mut().unwrap().inline_threshold = 30;
            OPTIONS.as_mut().unwrap().inline_max_iterations = 1;
        }
        let result = hir_string("test");
        unsafe {
            OPTIONS.as_mut().unwrap().inline_threshold = old_threshold;
            OPTIONS.as_mut().unwrap().inline_max_iterations = old_max_iterations;
        }

        assert!(result.contains("PushInlineFrame"),
            "Expected outer to be inlined with inline_max_iterations=1:\n{result}");
        assert!(result.contains(" = SendDirect "),
            "Expected the Send inside the final inlined body to be specialized to SendDirect:\n{result}");
        assert!(!result.contains(" = Send "),
            "Expected no unspecialized Send after the final specialization round:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, outer@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          PatchPoint MethodRedefined(Object@0x1008, inner@0x1048, cme:0x1050)
          v43:BasicObject = SendDirect v23, 0x1078, :inner (0x1088), v10
          CheckInterrupts
          PopInlineFrame
          Return v43
        ");
    }

    #[test]
    fn test_inline_budget_rejects_when_exceeded() {
        // The same workload as test_inline_arithmetic_method, which we know inlines
        // successfully under the default settings (budget=500, threshold=30). Setting
        // the budget to 1 forces should_inline to bail on the budget check before
        // reaching any other rejection reason. To verify the budget specifically is
        // what blocked the inline (not e.g. the size threshold or a parameter-shape
        // check), we read the inline_reject_budget_exceeded counter and confirm it
        // incremented while inline_method_count did not.
        eval("
            def add_one(x)
              x + 1
            end
            def test(n)
              add_one(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let budget_rejects_before = counters.inline_reject_budget_exceeded;
        let inline_count_before = counters.inline_method_count;

        let old_threshold = get_option!(inline_threshold);
        let old_budget = get_option!(inline_budget);
        unsafe {
            OPTIONS.as_mut().unwrap().inline_threshold = 30;
            OPTIONS.as_mut().unwrap().inline_budget = 1;
        }
        let result = hir_string("test");
        unsafe {
            OPTIONS.as_mut().unwrap().inline_threshold = old_threshold;
            OPTIONS.as_mut().unwrap().inline_budget = old_budget;
        }

        let budget_rejects_after = counters.inline_reject_budget_exceeded;
        let inline_count_after = counters.inline_method_count;

        assert!(budget_rejects_after > budget_rejects_before,
            "Expected inline_reject_budget_exceeded to increment, but it stayed at {budget_rejects_before}");
        assert_eq!(inline_count_after, inline_count_before,
            "Expected no successful inlines under budget=1, but inline_method_count went from {inline_count_before} to {inline_count_after}");

        // Belt-and-braces: the resulting HIR also reflects no inlining took place.
        assert!(result.contains("SendDirect"),
            "Expected SendDirect to remain in HIR when budget is exceeded:\n{result}");
        assert!(!result.contains("PushInlineFrame"),
            "Expected no PushInlineFrame in HIR when budget is exceeded:\n{result}");
    }

    #[test]
    fn test_inline_method_with_all_optionals_omitted() {
        // Caller fills 0 optionals: both `b` and `c` defaults must run inside the inlined
        // body. We pick `jit_entry_blocks[0]` so the body's default-init chain executes
        // and assigns `b = 10`, `c = 100` before the post-default body adds them.
        eval("
            def add_opts(a, b = 10, c = 100)
              a + b + c
            end
            def test(n)
              add_opts(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_opts to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, add_opts@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          v31:Fixnum[10] = Const Value(10)
          v40:Fixnum[100] = Const Value(100)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v70:Fixnum = GuardType v10, Fixnum recompile
          v71:Fixnum = FixnumAdd v70, v31
          v75:Fixnum = FixnumAdd v71, v40
          CheckInterrupts
          PopInlineFrame
          Return v75
        ");
    }

    #[test]
    fn test_inline_method_with_some_optionals_supplied() {
        // Caller fills 1 of 2 optionals: only `c`'s default should run. We pick
        // `jit_entry_blocks[1]`, whose target enters the body just before the `c`
        // default-init code so `b` is taken from the caller and `c` is filled in.
        eval("
            def add_opts(a, b = 10, c = 100)
              a + b + c
            end
            def test(n)
              add_opts(n, 20)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_opts to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[20] = Const Value(20)
          PatchPoint MethodRedefined(Object@0x1008, add_opts@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v25 (0x1040), v10, v16
          v42:Fixnum[100] = Const Value(100)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v71:Fixnum = GuardType v10, Fixnum recompile
          v72:Fixnum = FixnumAdd v71, v16
          v76:Fixnum = FixnumAdd v72, v42
          CheckInterrupts
          PopInlineFrame
          Return v76
        ");
    }

    #[test]
    fn test_inline_method_with_rescue_handler() {
        eval("
            def maybe_rescue(x)
              begin
                x + 1
              rescue StandardError
                0
              end
            end
            def test(n)
              maybe_rescue(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected maybe_rescue to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, maybe_rescue@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          v31:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v46:Fixnum = GuardType v10, Fixnum recompile
          v47:Fixnum = FixnumAdd v46, v31
          CheckInterrupts
          PopInlineFrame
          Return v47
        ");
    }

    #[test]
    fn test_inline_rejects_callees_on_deny_list() {
        // The `--zjit-inline-deny=...` knob lists qualified method names that
        // should_inline must refuse to inline, regardless of any other heuristic
        // outcome. The match runs before size/parameter/budget checks so the
        // signal is unambiguous when reading stats. The counter check pins the
        // rejection cause to the deny list specifically; an HIR-only check could
        // pass for any number of unrelated reasons that also leave SendDirect
        // in place.
        eval("
            def add_one(x)
              x + 1
            end
            def test(n)
              add_one(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let denied_rejects_before = counters.inline_reject_denied;
        let inline_count_before = counters.inline_method_count;

        let old_deny = get_option!(inline_deny).clone();
        unsafe {
            OPTIONS.as_mut().unwrap().inline_deny.insert("Object#add_one".to_string());
        }
        let result = hir_string_with_inlining("test");
        unsafe {
            OPTIONS.as_mut().unwrap().inline_deny = old_deny;
        }

        let denied_rejects_after = counters.inline_reject_denied;
        let inline_count_after = counters.inline_method_count;

        assert!(denied_rejects_after > denied_rejects_before,
            "Expected inline_reject_denied to increment for Object#add_one, but it stayed at {denied_rejects_before}");
        assert_eq!(inline_count_after, inline_count_before,
            "Expected no inlines for Object#add_one when on the deny list, but inline_method_count went from {inline_count_before} to {inline_count_after}");

        assert!(result.contains("SendDirect"),
            "Expected SendDirect to remain in HIR when callee is on the deny list:\n{result}");
        assert!(!result.contains("PushInlineFrame"),
            "Expected no PushInlineFrame in HIR when callee is on the deny list:\n{result}");
    }

    #[test]
    fn test_inline_method_with_invokesuper() {
        eval("
            class Parent
              def greet = 'hi'
            end
            class Child < Parent
              def greet = super + '!'
            end
            child = Child.new
            def test(c) = c.greet
            test(child)
            test(child)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected Child#greet to be inlined, but inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in HIR when inlining a super-containing callee:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :c@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :c@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint NoSingletonClass(Child@0x1008)
          PatchPoint MethodRedefined(Child@0x1008, greet@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact:Child] = GuardType v10, ObjectSubclass[class_exact:Child] recompile
          PushInlineFrame v23 (0x1040)
          PatchPoint MethodRedefined(Parent@0x1048, greet@0x1010, cme:0x1050)
          v46:CPtr = GetEP 0
          v47:RubyValue = LoadField v46, :VM_ENV_DATA_INDEX_ME_CREF@0x1078
          v48:CallableMethodEntry[VALUE(0x1018)] = GuardBitEquals v47, Value(VALUE(0x1018))
          v49:RubyValue = LoadField v46, :VM_ENV_DATA_INDEX_SPECVAL@0x1079
          v50:FalseClass = GuardBitEquals v49, Value(false)
          PushInlineFrame v23 (0x1040)
          v61:StringExact[VALUE(0x1080)] = Const Value(VALUE(0x1080))
          v62:StringExact = StringCopy v61
          CheckInterrupts
          PopInlineFrame
          v32:StringExact[VALUE(0x1088)] = Const Value(VALUE(0x1088))
          v33:StringExact = StringCopy v32
          PatchPoint NoSingletonClass(String@0x1090)
          PatchPoint MethodRedefined(String@0x1090, +@0x1098, cme:0x10a0)
          v56:BasicObject = CCallWithFrame v62, :String#+@0x10c8, v33
          CheckInterrupts
          PopInlineFrame
          Return v56
        ");
    }

    #[test]
    fn test_inline_method_with_all_optionals_supplied() {
        // Caller fills every optional: no default-init code runs. We pick the last
        // `jit_entry_blocks` entry, which lands directly in the post-default body.
        eval("
            def add_opts(a, b = 10, c = 100)
              a + b + c
            end
            def test(n)
              add_opts(n, 20, 200)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_opts to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[20] = Const Value(20)
          v18:Fixnum[200] = Const Value(200)
          PatchPoint MethodRedefined(Object@0x1008, add_opts@0x1010, cme:0x1018)
          v27:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v27 (0x1040), v10, v16, v18
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v72:Fixnum = GuardType v10, Fixnum recompile
          v73:Fixnum = FixnumAdd v72, v16
          v77:Fixnum = FixnumAdd v73, v18
          CheckInterrupts
          PopInlineFrame
          Return v77
        ");
    }

    #[test]
    fn test_inline_method_with_leading_optional_post_required() {
        // Callee shape `def m(a = 10, b)` has lead_num=0, opt_num=1, post_num=1.
        // The caller passes one positional, so the optional `a` falls through to
        // its default and `b` takes the lone caller arg. The inliner must shift
        // the post-required arg index past the gap of the unfilled optional.
        eval("
            def add_opt_post(a = 10, b)
              a + b
            end
            def test(n)
              add_opt_post(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_opt_post to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, add_opt_post@0x1010, cme:0x1018)
          v23:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v23 (0x1040), v10
          v30:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v55:Fixnum = GuardType v10, Fixnum
          v56:Fixnum = FixnumAdd v30, v55
          CheckInterrupts
          PopInlineFrame
          Return v56
        ");
    }

    #[test]
    fn test_inline_method_with_required_optional_post_all_omitted() {
        // Callee shape `def m(a, b = 10, c)` has lead_num=1, opt_num=1, post_num=1.
        // Calling with two positionals fills `a` and `c`; `b` falls through to its
        // default. The inliner must enter the body via jit_entry_blocks[0] so the
        // default-init code for `b` runs, and shift `c`'s arg index past the gap.
        eval("
            def add_lead_opt_post(a, b = 10, c)
              a + b + c
            end
            def test(n)
              add_lead_opt_post(n, 200)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_lead_opt_post to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[200] = Const Value(200)
          PatchPoint MethodRedefined(Object@0x1008, add_lead_opt_post@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v25 (0x1040), v10, v16
          v33:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v62:Fixnum = GuardType v10, Fixnum recompile
          v63:Fixnum = FixnumAdd v62, v33
          v67:Fixnum = FixnumAdd v63, v16
          CheckInterrupts
          PopInlineFrame
          Return v67
        ");
    }

    #[test]
    fn test_inline_method_with_required_keyword() {
        eval("
            def add_kw(a, b:)
              a + b
            end
            def test(n)
              add_kw(n, b: 5)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_kw to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Object@0x1008, add_kw@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v42:Fixnum[0] = Const Value(0)
          PushInlineFrame v25 (0x1040), v10, v16
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v49:Fixnum = GuardType v10, Fixnum recompile
          v50:Fixnum = FixnumAdd v49, v16
          CheckInterrupts
          PopInlineFrame
          Return v50
        ");
    }

    #[test]
    fn test_inline_method_with_optional_keyword_supplied() {
        eval("
            def add_optkw(a, b: 10)
              a + b
            end
            def test(n)
              add_optkw(n, b: 50)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_optkw to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[50] = Const Value(50)
          PatchPoint MethodRedefined(Object@0x1008, add_optkw@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v42:Fixnum[0] = Const Value(0)
          PushInlineFrame v25 (0x1040), v10, v16
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v49:Fixnum = GuardType v10, Fixnum recompile
          v50:Fixnum = FixnumAdd v49, v16
          CheckInterrupts
          PopInlineFrame
          Return v50
        ");
    }

    #[test]
    fn test_inline_method_with_optional_keyword_omitted_constant_default() {
        eval("
            def add_optkw(a, b: 10)
              a + b
            end
            def test(n)
              add_optkw(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_optkw to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v22:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Object@0x1008, add_optkw@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v42:Fixnum[0] = Const Value(0)
          PushInlineFrame v25 (0x1040), v10, v22
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v49:Fixnum = GuardType v10, Fixnum recompile
          v50:Fixnum = FixnumAdd v49, v22
          CheckInterrupts
          PopInlineFrame
          Return v50
        ");
    }

    #[test]
    fn test_inline_method_with_keywords_reordered() {
        // Caller passes keywords in an order that doesn't match the callee's declaration.
        eval("
            def add_kws(a, b:, c:)
              a * 100 + b * 10 + c
            end
            def test(n)
              add_kws(n, c: 3, b: 2)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_kws to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[3] = Const Value(3)
          v18:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1008, add_kws@0x1010, cme:0x1018)
          v28:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v60:Fixnum[0] = Const Value(0)
          PushInlineFrame v28 (0x1040), v10, v18, v16
          v39:Fixnum[100] = Const Value(100)
          PatchPoint MethodRedefined(Integer@0x1048, *@0x1050, cme:0x1058)
          v67:Fixnum = GuardType v10, Fixnum recompile
          v68:Fixnum = FixnumMult v67, v39
          v81:Fixnum[20] = Const Value(20)
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1080, cme:0x1088)
          v76:Fixnum = FixnumAdd v68, v81
          v80:Fixnum = FixnumAdd v76, v16
          CheckInterrupts
          PopInlineFrame
          Return v80
        ");
    }

    #[test]
    fn test_inline_method_with_optional_keyword_omitted_nonconstant_default() {
        // Optional keyword with a non-constant default expression (`b: a * 2`) omitted by the caller.
        eval("
            def add_optkw_dyn(a, b: a * 2)
              a + b
            end
            def test(n)
              add_optkw_dyn(n)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_optkw_dyn to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v22:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Object@0x1008, add_optkw_dyn@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v63:Fixnum[1] = Const Value(1)
          PushInlineFrame v25 (0x1040), v10, v22
          v33:BoolExact = FixnumBitCheck v63, 0
          CheckInterrupts
          v36:CBool = Test v33
          CondBranch v36, bb6(v25, v10, v22, v63), bb7()
        bb7():
          v42:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1048, *@0x1050, cme:0x1058)
          v70:Fixnum = GuardType v10, Fixnum recompile
          v71:Fixnum = FixnumMult v70, v42
          Jump bb6(v25, v70, v71, v63)
        bb6(v48:ObjectSubclass[class_exact*:Object@VALUE(0x1008)], v49:BasicObject, v50:NilClass|Fixnum, v51:Fixnum[1]):
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1080, cme:0x1088)
          v74:Fixnum = GuardType v49, Fixnum recompile
          v75:Fixnum = GuardType v50, Fixnum
          v76:Fixnum = FixnumAdd v74, v75
          CheckInterrupts
          PopInlineFrame
          Return v76
        ");
    }

    #[test]
    fn test_inline_method_with_required_optional_post_all_supplied() {
        // Same callee shape as above (lead+opt+post) but the caller fills the
        // optional explicitly. We pick jit_entry_blocks[1] so no default-init code
        // runs and every local takes a caller arg directly.
        eval("
            def add_lead_opt_post(a, b = 10, c)
              a + b + c
            end
            def test(n)
              add_lead_opt_post(n, 20, 300)
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected add_lead_opt_post to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          v16:Fixnum[20] = Const Value(20)
          v18:Fixnum[300] = Const Value(300)
          PatchPoint MethodRedefined(Object@0x1008, add_lead_opt_post@0x1010, cme:0x1018)
          v27:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v27 (0x1040), v10, v16, v18
          PatchPoint MethodRedefined(Integer@0x1048, +@0x1050, cme:0x1058)
          v63:Fixnum = GuardType v10, Fixnum recompile
          v64:Fixnum = FixnumAdd v63, v16
          v68:Fixnum = FixnumAdd v64, v18
          CheckInterrupts
          PopInlineFrame
          Return v68
        ");
    }

    #[test]
    fn test_inline_method_with_invokeblock() {
        // The callee dispatches to the caller-supplied literal block via `yield`.
        // The block handler is established by the SPECVAL written into the inlined
        // frame by PushInlineFrame, and the `yield` lowers to an InvokeBlock that
        // reads it off the live CFP at runtime.
        eval("
            def with_yield(x)
              yield x
            end
            def test(n)
              with_yield(n) { |x| x + 2 }
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected with_yield to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, with_yield@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          PushInlineFrame v25 (0x1040), v10
          v33:BasicObject = InvokeBlock v10 # SendFallbackReason: InvokeBlock: not yet specialized
          CheckInterrupts
          PopInlineFrame
          PatchPoint NoEPEscape(test)
          Return v33
        ");
    }

    #[test]
    fn test_inline_method_with_block_param() {
        // The callee captures the caller-supplied literal block in a `&block`
        // parameter and invokes it with `block.call`. Inlining must preserve the
        // block handler so the reified Proc dispatches to the right block.
        eval("
            def with_block_param(x, &block)
              block.call(x)
            end
            def test(n)
              with_block_param(n) { |x| x + 2 }
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected with_block_param to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:6:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, with_block_param@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v52:NilClass = Const Value(nil)
          PushInlineFrame v25 (0x1040), v10
          v35:CPtr = GetEP 0
          v36:CUInt64 = LoadField v35, :VM_ENV_DATA_INDEX_FLAGS@0x1048
          v37:CBool = IsBlockParamModified v36
          CondBranch v37, bb6(), bb7()
        bb6():
          v39:BasicObject = LoadField v35, :block@0x1049
          Jump bb8(v39, v39)
        bb7():
          v41:CInt64 = LoadField v35, :VM_ENV_DATA_INDEX_SPECVAL@0x104a
          v42:CInt64 = GuardAnyBitSet v41, CUInt64(1) recompile
          v43:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1050))
          Jump bb8(v43, v52)
        bb8(v33:BasicObject, v34:BasicObject):
          v47:BasicObject = Send v33, :call, v10 # SendFallbackReason: SendWithoutBlock: unsupported optimized method type BlockCall
          CheckInterrupts
          PopInlineFrame
          PatchPoint NoEPEscape(test)
          Return v47
        ");
    }

    #[test]
    fn test_inline_method_that_forwards_block_arg() {
        eval("
            def inner(x)
              yield x
            end
            def callee(x, &block)
              inner(x, &block)
            end
            def test(n)
              callee(n) { |x| x + 2 }
            end
            test(1)
            test(1)
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected callee to be inlined despite forwarding its block.\nHIR:\n{result}");
        assert_eq!(result.matches("PushInlineFrame").count(), 1,
            "Expected only `callee` to be inlined, not `inner`:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:9:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :n@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :n@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
          PatchPoint MethodRedefined(Object@0x1008, callee@0x1010, cme:0x1018)
          v25:ObjectSubclass[class_exact*:Object@VALUE(0x1008)] = GuardType v9, ObjectSubclass[class_exact*:Object@VALUE(0x1008)] recompile
          v53:NilClass = Const Value(nil)
          PushInlineFrame v25 (0x1040), v10
          v37:CPtr = GetEP 0
          v38:CUInt64 = LoadField v37, :VM_ENV_DATA_INDEX_FLAGS@0x1048
          v39:CBool = IsBlockParamModified v38
          CondBranch v39, bb6(), bb7()
        bb6():
          v41:BasicObject = LoadField v37, :block@0x1049
          Jump bb8(v41, v41)
        bb7():
          v43:CInt64 = LoadField v37, :VM_ENV_DATA_INDEX_SPECVAL@0x104a
          v44:CInt64 = GuardAnyBitSet v43, CUInt64(1) recompile
          v45:ObjectSubclass[BlockParamProxy] = Const Value(VALUE(0x1050))
          Jump bb8(v45, v53)
        bb8(v35:BasicObject, v36:BasicObject):
          v48:BasicObject = Send v25, &block, :inner, v10, v35 # SendFallbackReason: Send: block argument is not nil
          CheckInterrupts
          PopInlineFrame
          PatchPoint NoEPEscape(test)
          Return v48
        ");
    }

    #[test]
    fn test_inline_object_new_no_escape() {
        // Mirrors the object-new-no-escape benchmark from ruby-bench.
        eval("
            class Point
              attr_reader :x, :y
              def initialize(x, y)
                @x = x
                @y = y
              end

              def ==(other)
                @x == other.x && @y == other.y
              end
            end

            def test
              Point.new(1, 2) == Point.new(1, 2)
            end
            test
            test
        ");
        let counters = crate::state::ZJITState::get_counters();
        let inline_count_before = counters.inline_method_count;

        let result = hir_string_with_inlining("test");

        assert!(counters.inline_method_count > inline_count_before,
            "Expected Point#initialize / Point#== to be inlined, inline_method_count did not increment.\nHIR:\n{result}");
        assert!(result.contains("PushInlineFrame"),
            "Expected PushInlineFrame in inlined HIR:\n{result}");
        assert!(!result.contains("SendDirect"),
            "Expected SendDirect to be replaced after inlining:\n{result}");

        assert_snapshot!(result, @"
        fn test@<compiled>:15:
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
          PatchPoint StableConstantNames(0x1000, Point)
          v12:ClassSubclass[Point@0x1008] = Const Value(VALUE(0x1008))
          v14:NilClass = Const Value(nil)
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Point@0x1008, new@0x1009, cme:0x1010)
          v91:ObjectSubclass[class_exact:Point] = ObjectAllocClass Point:VALUE(0x1008)
          PatchPoint NoSingletonClass(Point@0x1008)
          PatchPoint MethodRedefined(Point@0x1008, initialize@0x1038, cme:0x1040)
          PushInlineFrame v91 (0x1068), v17, v19
          v122:CShape = LoadField v91, :shape_id@0x1070
          v123:CShape[0x1071] = GuardBitEquals v122, CShape(0x1071) recompile
          StoreField v91, :@x@0x1072, v17
          WriteBarrier v91, v17
          v126:CShape[0x1073] = Const CShape(0x1073)
          StoreField v91, :shape_id@0x1070, v126
          PatchPoint NoEPEscape(initialize)
          PatchPoint SingleRactorMode
          StoreField v91, :@y@0x1074, v19
          WriteBarrier v91, v19
          v141:CShape[0x1075] = Const CShape(0x1075)
          StoreField v91, :shape_id@0x1070, v141
          CheckInterrupts
          PopInlineFrame
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1078, Point)
          v47:ClassSubclass[Point@0x1008] = Const Value(VALUE(0x1008))
          v49:NilClass = Const Value(nil)
          v52:Fixnum[1] = Const Value(1)
          v54:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Point@0x1008, new@0x1009, cme:0x1010)
          v101:ObjectSubclass[class_exact:Point] = ObjectAllocClass Point:VALUE(0x1008)
          PatchPoint NoSingletonClass(Point@0x1008)
          PatchPoint MethodRedefined(Point@0x1008, initialize@0x1038, cme:0x1040)
          PushInlineFrame v101 (0x1068), v52, v54
          v161:CShape = LoadField v101, :shape_id@0x1070
          v162:CShape[0x1071] = GuardBitEquals v161, CShape(0x1071) recompile
          StoreField v101, :@x@0x1072, v52
          WriteBarrier v101, v52
          v165:CShape[0x1073] = Const CShape(0x1073)
          StoreField v101, :shape_id@0x1070, v165
          PatchPoint NoEPEscape(initialize)
          PatchPoint SingleRactorMode
          StoreField v101, :@y@0x1074, v54
          WriteBarrier v101, v54
          v180:CShape[0x1075] = Const CShape(0x1075)
          StoreField v101, :shape_id@0x1070, v180
          CheckInterrupts
          PopInlineFrame
          PatchPoint NoSingletonClass(Point@0x1008)
          PatchPoint MethodRedefined(Point@0x1008, ==@0x1080, cme:0x1088)
          PushInlineFrame v91 (0x1068), v101
          PatchPoint SingleRactorMode
          v198:CShape = LoadField v91, :shape_id@0x1070
          v199:CShape[0x1075] = GuardBitEquals v198, CShape(0x1075) recompile
          v200:BasicObject = LoadField v91, :@x@0x1072
          PatchPoint NoEPEscape(==)
          PatchPoint MethodRedefined(Point@0x1008, x@0x10b0, cme:0x10b8)
          PatchPoint MethodRedefined(Integer@0x10e0, ==@0x1080, cme:0x10e8)
          v255:Fixnum = GuardType v200, Fixnum recompile
          v257:BoolExact = FixnumEq v255, v52
          v212:CBool = Test v257
          v213:FalseClass = RefineType v257, Falsy
          CondBranch v212, bb19(), bb18(v91, v101, v213)
        bb19():
          PatchPoint SingleRactorMode
          v220:CShape = LoadField v91, :shape_id@0x1070
          v221:CShape[0x1075] = GuardBitEquals v220, CShape(0x1075) recompile
          v222:BasicObject = LoadField v91, :@y@0x1074
          PatchPoint NoEPEscape(==)
          PatchPoint NoSingletonClass(Point@0x1008)
          PatchPoint MethodRedefined(Point@0x1008, y@0x1110, cme:0x1118)
          v262:CShape = LoadField v101, :shape_id@0x1070
          v263:CShape[0x1075] = GuardBitEquals v262, CShape(0x1075) recompile
          v264:BasicObject = LoadField v101, :@y@0x1074
          PatchPoint MethodRedefined(Integer@0x10e0, ==@0x1080, cme:0x10e8)
          v267:Fixnum = GuardType v222, Fixnum recompile
          v268:Fixnum = GuardType v264, Fixnum
          v269:BoolExact = FixnumEq v267, v268
          Jump bb18(v91, v101, v269)
        bb18(v232:ObjectSubclass[class_exact:Point], v233:ObjectSubclass[class_exact:Point], v234:BoolExact):
          CheckInterrupts
          PopInlineFrame
          Return v234
        ");
    }

    #[test]
    fn test_ccall_with_frame_too_many_args_result_used_in_later_block() {
        unsafe extern "C" fn test_seven_args(
            _self: VALUE,
            a: VALUE,
            b: VALUE,
            c: VALUE,
            d: VALUE,
            e: VALUE,
            f: VALUE,
            g: VALUE,
        ) -> VALUE {
            unsafe { rb_ary_new_from_args(7, a, b, c, d, e, f, g) }
        }

        with_rubyvm(|| {
            let klass = define_class("ZJITSevenArgs", unsafe { rb_cObject });
            unsafe {
                rb_define_method(
                    klass,
                    c"seven".as_ptr(),
                    Some(std::mem::transmute::<
                        unsafe extern "C" fn(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) -> VALUE,
                        unsafe extern "C" fn(VALUE) -> VALUE,
                    >(test_seven_args)),
                    7,
                );
            }
        });

        eval(r#"
            def test(obj, flag)
              priceable = obj.seven(1, 2, 3, 4, 5, 6, 7)
              if flag
                priceable
              else
                nil
              end
            end

            obj = ZJITSevenArgs.new
            test(obj, true)  # profile receiver class
        "#);
        assert_snapshot!(hir_string("test"), @"
        fn test@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :obj@0x1000
          v4:BasicObject = LoadField v2, :flag@0x1001
          v5:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4, v5)
        bb2():
          EntryPoint JIT(0)
          v8:BasicObject = LoadArg :self@0
          v9:BasicObject = LoadArg :obj@1
          v10:BasicObject = LoadArg :flag@2
          v11:NilClass = Const Value(nil)
          Jump bb3(v8, v9, v10, v11)
        bb3(v13:BasicObject, v14:BasicObject, v15:BasicObject, v16:NilClass):
          v21:Fixnum[1] = Const Value(1)
          v23:Fixnum[2] = Const Value(2)
          v25:Fixnum[3] = Const Value(3)
          v27:Fixnum[4] = Const Value(4)
          v29:Fixnum[5] = Const Value(5)
          v31:Fixnum[6] = Const Value(6)
          v33:Fixnum[7] = Const Value(7)
          v35:BasicObject = Send v14, :seven, v21, v23, v25, v27, v29, v31, v33 # SendFallbackReason: Too many arguments for LIR
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          v43:CBool = Test v15
          v44:Falsy = RefineType v15, Falsy
          CondBranch v43, bb5(), bb4(v13, v14, v44, v35)
        bb5():
          v46:Truthy = RefineType v15, Truthy
          CheckInterrupts
          Return v35
        bb4(v53:BasicObject, v54:BasicObject, v55:Falsy, v56:BasicObject):
          v60:NilClass = Const Value(nil)
          CheckInterrupts
          Return v60
        ");
    }
}
