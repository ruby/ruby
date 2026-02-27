#[cfg(test)]
mod hir_opt_tests {
    use crate::hir::*;

    use crate::{hir_strings, options::*};
    use insta::assert_snapshot;
    use crate::hir::tests::hir_build_tests::assert_contains_opcode;

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
          v22:TrueClass = RefineType v13, Truthy
          v25:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v13:FalseClass = Const Value(false)
          CheckInterrupts
          v20:FalseClass = RefineType v13, Falsy
          v35:Fixnum[4] = Const Value(4)
          CheckInterrupts
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          v35:Fixnum[6] = Const Value(6)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_fold_fixnum_sub() {
        eval("
            def test
              5 - 3 - 1
            end
        ");
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
          v10:Fixnum[5] = Const Value(5)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          v35:Fixnum[1] = Const Value(1)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v35
        ");
    }

    #[test]
    fn test_fold_fixnum_sub_large_negative_result() {
        eval("
            def test
              0 - 1073741825
            end
        ");
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
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[1073741825] = Const Value(1073741825)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v25:Fixnum[-1073741825] = Const Value(-1073741825)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_mult() {
        eval("
            def test
              6 * 7
            end
        ");
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
          v10:Fixnum[6] = Const Value(6)
          v12:Fixnum[7] = Const Value(7)
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v25:Fixnum[42] = Const Value(42)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
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
          v35:Fixnum = GuardType v10, Fixnum
          v47:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          v21:Fixnum[0] = Const Value(0)
          v40:Fixnum = GuardType v10, Fixnum
          v48:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint MethodRedefined(Integer@0x1008, +@0x1040, cme:0x1048)
          v49:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v49
        ");
    }


    #[test]
    fn test_fold_fixnum_mod_zero_by_zero() {
        eval("
            def test
              0 % 0
            end
        ");
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
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v23:Fixnum = FixnumMod v10, v12
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:Fixnum[11] = Const Value(11)
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v23:Fixnum = FixnumMod v10, v12
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[11] = Const Value(11)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v25:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_mod() {
        eval("
            def test
              11 % 3
            end
        ");
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
          v10:Fixnum[11] = Const Value(11)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v25:Fixnum[2] = Const Value(2)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative_numerator() {
        eval("
            def test
              -7 % 3
            end
        ");
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
          v10:Fixnum[-7] = Const Value(-7)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v25:Fixnum[2] = Const Value(2)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative_denominator() {
        eval("
            def test
              7 % -3
            end
        ");
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
          v10:Fixnum[7] = Const Value(7)
          v12:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v25:Fixnum[-2] = Const Value(-2)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_fixnum_mod_negative() {
        eval("
            def test
              -7 % -3
            end
        ");
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
          v10:Fixnum[-7] = Const Value(-7)
          v12:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v25:Fixnum[-1] = Const Value(-1)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
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
          v24:Fixnum[7] = Const Value(7)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v24:Fixnum[-2] = Const Value(-2)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          IncrCounter inline_cfunc_optimized_send_count
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
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v43:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <=@0x1008, cme:0x1010)
          v60:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v62:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v37:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >@0x1008, cme:0x1010)
          v43:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >=@0x1008, cme:0x1010)
          v60:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v62:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v37:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v43:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v33:Fixnum[4] = Const Value(4)
          CheckInterrupts
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
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v43:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v44:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v24:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v44:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v33:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v33
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
          v30:HeapObject[class_exact:CustomEq] = GuardType v10, HeapObject[class_exact:CustomEq]
          v31:BoolExact = CCallWithFrame v30, :BasicObject#!=@0x1040, v10
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:Fixnum = FixnumAdd v26, v15
          IncrCounter inline_cfunc_optimized_send_count
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
    fn test_optimize_top_level_call_into_send_direct() {
        eval("
            def foo = []
            def test
              foo
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v20:BasicObject = SendDirect v19, 0x1038, :foo (0x1048)
          CheckInterrupts
          Return v20
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_no_inline_nonparam_local_return() {
        // Methods that return non-parameter local variables should NOT be inlined,
        // because the local variable index will be out of bounds for args.
        // The method must have a parameter so param_size > 0, and return a local
        // that's not a parameter so local_idx >= param_size.
        // Use dead code (if false) to create a local without initialization instructions,
        // resulting in just getlocal + leave which enters the inlining code path.
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
        assert_snapshot!(hir_string("test"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendDirect v21, 0x1038, :foo (0x1048), v11
          CheckInterrupts
          Return v22
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
          v25:ArraySubclass[class_exact:C] = GuardType v10, ArraySubclass[class_exact:C]
          v26:BasicObject = SendDirect v25, 0x1040, :fun_new_map (0x1050)
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :o@0x1058
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v27:BasicObject = CCallWithFrame v26, :Enumerable#bar@0x1040, block=0x1048
          v16:CPtr = GetEP 0
          v17:BasicObject = LoadField v16, :o@0x1050
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
          v24:ArrayExact = GuardType v10, ArrayExact
          v25:BasicObject = CCallWithFrame v24, :Array#length@0x1040
          CheckInterrupts
          Return v25
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
          v11:BasicObject = Send v6, :foo # SendFallbackReason: SendWithoutBlock: unsupported method type Null
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_optimize_private_top_level_call() {
        eval("
            def foo = []
            private :foo
            def test
              foo
            end
            test; test
        ");
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v20:BasicObject = SendDirect v19, 0x1038, :foo (0x1048)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_optimize_top_level_call_with_overloaded_cme() {
        eval("
            def test
              Integer(3)
            end
            test; test
        ");
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, Integer@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendDirect v21, 0x1038, :Integer (0x1048), v11
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_optimize_top_level_call_with_args_into_send_direct() {
        eval("
            def foo(a, b) = []
            def test
              foo 1, 2
            end
            test; test
        ");
        assert_snapshot!(hir_string("test"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v24:BasicObject = SendDirect v23, 0x1038, :foo (0x1048), v11, v13
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_optimize_top_level_sends_into_send_direct() {
        eval("
            def foo = []
            def bar = []
            def test
              foo
              bar
            end
            test; test
        ");
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, bar@0x1050, cme:0x1058)
          v28:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v29:BasicObject = SendDirect v28, 0x1038, :bar (0x1048)
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_optimize_send_direct_no_optionals_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo
            test
        ");
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v20:BasicObject = SendDirect v19, 0x1038, :foo (0x1048)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_optimize_send_direct_one_optional_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo 3
            test
        ");
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendDirect v21, 0x1038, :foo (0x1048), v11
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_optimize_send_direct_all_optionals_passed() {
        eval("
            def foo(a=1, b=2) = a + b
            def test = foo 3, 4
            test
        ");
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
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v24:BasicObject = SendDirect v23, 0x1038, :foo (0x1048), v11, v13
          CheckInterrupts
          Return v24
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v45:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v46:BasicObject = SendDirect v45, 0x1038, :target (0x1048)
          v14:Fixnum[10] = Const Value(10)
          v16:Fixnum[20] = Const Value(20)
          v18:Fixnum[30] = Const Value(30)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v49:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v50:BasicObject = SendDirect v49, 0x1038, :target (0x1048), v14, v16, v18
          v24:Fixnum[10] = Const Value(10)
          v26:Fixnum[20] = Const Value(20)
          v28:Fixnum[30] = Const Value(30)
          v30:Fixnum[40] = Const Value(40)
          v32:Fixnum[50] = Const Value(50)
          v34:BasicObject = Send v6, :target, v24, v26, v28, v30, v32 # SendFallbackReason: Argument count does not match parameter count
          v37:ArrayExact = NewArray v46, v50, v34
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
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          PatchPoint NoSingletonClass(Object@0x1008)
          PatchPoint MethodRedefined(Object@0x1008, puts@0x1010, cme:0x1018)
          v23:HeapObject[class_exact*:Object@VALUE(0x1008)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1008)]
          v24:BasicObject = CCallVariadic v23, :Kernel#puts@0x1040, v12
          CheckInterrupts
          Return v24
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
          v27:Fixnum = GuardType v12, Fixnum
          IncrCounter inline_iseq_optimized_send_count
          v30:Fixnum[100] = Const Value(100)
          CheckInterrupts
          Return v30
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
          v28:Fixnum = GuardType v12, Fixnum
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAdd v28, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:Fixnum = FixnumAdd v26, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:Fixnum = FixnumAdd v14, v26
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
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
          v28:Fixnum = GuardType v12, Fixnum
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAref v28, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:Fixnum = GuardType v12, Fixnum
          v29:Fixnum = GuardType v13, Fixnum
          v30:BoolExact = FixnumLt v28, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:BoolExact = FixnumLt v26, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:BoolExact = FixnumLt v14, v26
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
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
    fn test_eliminate_new_array() {
        eval("
            def test()
              c = []
              5
            end
            test; test
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
          v27:ArrayExact = GuardType v10, ArrayExact
          v28:CInt64[0] = UnboxFixnum v15
          v29:CInt64 = ArrayLength v27
          v30:CInt64[0] = GuardLess v28, v29
          v31:CInt64[0] = Const CInt64(0)
          v32:CInt64[0] = GuardGreaterEq v30, v31
          v33:BasicObject = ArrayAref v27, v32
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v33
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
          v27:HashExact = GuardType v10, HashExact
          v28:BasicObject = HashAref v27, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          v34:Fixnum = FixnumDiv v32, v33
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          v34:Fixnum = FixnumMod v32, v33
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          v33:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:Fixnum = GuardType v12, Fixnum
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v34:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
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
          v23:Fixnum = GuardType v10, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn kernel_itself_known_type() {
        eval("
            def test = [].itself
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          v13:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string("test"), @r"
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
          v29:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, name@0x1018, cme:0x1020)
          IncrCounter inline_cfunc_optimized_send_count
          v34:StringExact|NilClass = CCall v29, :Module#name@0x1048
          PatchPoint NoEPEscape(test)
          v21:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v21
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v18:Class[C@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn core_classes_type_inference() {
        eval("
            def test = [String, Class, Module, BasicObject]
            test # Warm the constant cache
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v26:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Class)
          v29:Class[Class@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint StableConstantNames(0x1020, Module)
          v32:Class[Module@0x1028] = Const Value(VALUE(0x1028))
          PatchPoint StableConstantNames(0x1030, BasicObject)
          v35:Class[BasicObject@0x1038] = Const Value(VALUE(0x1038))
          v18:ArrayExact = NewArray v26, v29, v32, v35
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn module_instances_are_module_exact() {
        eval("
            def test = [Enumerable, Kernel]
            test # Warm the constant cache
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Enumerable)
          v22:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, Kernel)
          v25:ModuleExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          v14:ArrayExact = NewArray v22, v25
          CheckInterrupts
          Return v14
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
        assert_snapshot!(hir_string("test"), @r"
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
          v18:ModuleSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v18
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          v12:Fixnum[0] = Const Value(0)
          v14:BasicObject = Send v10, :itself, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:CPtr = GetEP 0
          v22:BoolExact = IsBlockGiven v21
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_kernel_block_given_p_in_block() {
        eval("
            TEST = proc { block_given? }
            TEST.call
        ");
        assert_snapshot!(hir_string_proc("TEST"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v21
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_cfunc_optimized_send_count
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
          IncrCounter inline_iseq_optimized_send_count
          v25:BasicObject = InvokeBuiltin leaf <inline_expr>, v14
          CheckInterrupts
          Return v25
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
          IncrCounter inline_iseq_optimized_send_count
          v33:BasicObject = InvokeBuiltin leaf <inline_expr>, v18
          CheckInterrupts
          Return v33
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, M)
          v20:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, class@0x1018, cme:0x1020)
          IncrCounter inline_iseq_optimized_send_count
          v26:Class[Module@0x1010] = Const Value(VALUE(0x1010))
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_send_direct_to_instance_method() {
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v24:BasicObject = SendDirect v23, 0x1040, :foo (0x1050)
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_send_direct_iseq_with_block() {
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn reload_local_across_send() {
        eval("
            def foo(&block) = 1
            def test
              a = 1
              foo {|| }
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v33:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v8, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :a@0x1038
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_rest() {
        eval("
            def foo(*args) = 1
            def test = foo 1
            test
            test
        ");
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          v13:BasicObject = Send v6, :foo, v11 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn dont_specialize_call_to_post_param_iseq() {
        eval("
            def foo(opt=80, post) = post
            def test = foo(10)
            test
        ");
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
          v11:Fixnum[10] = Const Value(10)
          IncrCounter complex_arg_pass_param_post
          v13:BasicObject = Send v6, :foo, v11 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v13
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v24:BasicObject = SendDirect v23, 0x1038, :foo (0x1048), v11, v13
          CheckInterrupts
          Return v24
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
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[1] = Const Value(1)
          v15:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v27:BasicObject = SendDirect v26, 0x1038, :foo (0x1048), v13, v15, v11
          CheckInterrupts
          Return v27
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
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v27:BasicObject = SendDirect v26, 0x1038, :foo (0x1048), v11, v15, v13
          CheckInterrupts
          Return v27
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
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v24:BasicObject = SendDirect v23, 0x1038, :foo (0x1048), v11, v13
          CheckInterrupts
          Return v24
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          v15:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v38:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v39:BasicObject = SendDirect v38, 0x1038, :foo (0x1048), v11, v13, v15
          v20:Fixnum[1] = Const Value(1)
          v22:Fixnum[2] = Const Value(2)
          v24:Fixnum[4] = Const Value(4)
          v26:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v43:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v44:BasicObject = SendDirect v43, 0x1038, :foo (0x1048), v20, v22, v26, v24
          v30:ArrayExact = NewArray v39, v44
          CheckInterrupts
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          v34:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v38:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v39:BasicObject = SendDirect v38, 0x1038, :foo (0x1048), v11, v13, v34
          v18:Fixnum[1] = Const Value(1)
          v20:Fixnum[2] = Const Value(2)
          v22:Fixnum[40] = Const Value(40)
          v24:Fixnum[30] = Const Value(30)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v43:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v44:BasicObject = SendDirect v43, 0x1038, :foo (0x1048), v18, v20, v24, v22
          v28:ArrayExact = NewArray v39, v44
          CheckInterrupts
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
          v11:Fixnum[6] = Const Value(6)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v49:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v50:BasicObject = SendDirect v49, 0x1038, :target (0x1048), v11
          v16:Fixnum[10] = Const Value(10)
          v18:Fixnum[20] = Const Value(20)
          v20:Fixnum[30] = Const Value(30)
          v22:Fixnum[6] = Const Value(6)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v53:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v54:BasicObject = SendDirect v53, 0x1038, :target (0x1048), v16, v18, v20, v22
          v27:Fixnum[10] = Const Value(10)
          v29:Fixnum[20] = Const Value(20)
          v31:Fixnum[30] = Const Value(30)
          v33:Fixnum[40] = Const Value(40)
          v35:Fixnum[50] = Const Value(50)
          v37:Fixnum[60] = Const Value(60)
          v39:BasicObject = Send v6, :target, v27, v29, v31, v33, v35, v37 # SendFallbackReason: Too many arguments for LIR
          v41:ArrayExact = NewArray v50, v54, v39
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
          v11:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendDirect v21, 0x1038, :foo (0x1048), v11
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_kwrest() {
        eval("
            def foo(**args) = 1
            def test = foo(a: 1)
            test
            test
        ");
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_kwrest
          v13:BasicObject = Send v6, :foo, v11 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v13
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
          v17:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendDirect v21, 0x1038, :foo (0x1048), v17
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_call_kwsplat() {
        eval("
            def foo(a:) = a
            def test = foo(**{a: 1})
            test
            test
        ");
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
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:HashExact = HashDup v11
          IncrCounter complex_arg_pass_caller_kw_splat
          v14:BasicObject = Send v6, :foo, v12 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_param_kwrest() {
        eval("
            def foo(**kwargs) = kwargs.keys
            def test = foo
            test
            test
        ");
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
          IncrCounter complex_arg_pass_param_kwrest
          v11:BasicObject = Send v6, :foo # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn dont_optimize_ccall_with_kwarg() {
        eval("
            def test = sprintf('%s', a: 1)
            test
            test
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
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          v14:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_caller_kwarg
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
          IncrCounter complex_arg_pass_caller_kwarg
          v24:BasicObject = Send v12, 0x1008, :each_line, v22 # SendFallbackReason: Complex argument passing
          v25:CPtr = GetEP 0
          v26:BasicObject = LoadField v25, :s@0x1030
          v27:BasicObject = LoadField v25, :a@0x1031
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn dont_replace_get_constant_path_with_empty_ic() {
        eval("
            def test = Kernel
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
          PatchPoint StableConstantNames(0x1000, Kernel)
          v18:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v18
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
        assert_snapshot!(hir_string("test"), @r"
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
          v18:Class[Foo::Bar::C@0x1008] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_opt_new_no_initialize() {
        eval("
            class C; end
            def test = C.new
            test
        ");
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v43:Class[C@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v46:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v46
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
        assert_snapshot!(hir_string("test"), @r"
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
          v46:Class[C@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v49:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          v52:BasicObject = SendDirect v49, 0x1068, :initialize (0x1078), v15
          CheckInterrupts
          CheckInterrupts
          Return v49
        ");
    }

    #[test]
    fn test_opt_new_object() {
        eval("
            def test = Object.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Object)
          v43:Class[Object@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Object@0x1008, new@0x1009, cme:0x1010)
          v46:ObjectExact = ObjectAllocClass Object:VALUE(0x1008)
          PatchPoint NoSingletonClass(Object@0x1008)
          PatchPoint MethodRedefined(Object@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v46
        ");
    }

    #[test]
    fn test_opt_new_basic_object() {
        eval("
            def test = BasicObject.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, BasicObject)
          v43:Class[BasicObject@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(BasicObject@0x1008, new@0x1009, cme:0x1010)
          v46:BasicObjectExact = ObjectAllocClass BasicObject:VALUE(0x1008)
          PatchPoint NoSingletonClass(BasicObject@0x1008)
          PatchPoint MethodRedefined(BasicObject@0x1008, initialize@0x1038, cme:0x1040)
          v50:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v46
        ");
    }

    #[test]
    fn test_opt_new_hash() {
        eval("
            def test = Hash.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Hash)
          v43:Class[Hash@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Hash@0x1008, new@0x1009, cme:0x1010)
          v46:HashExact = ObjectAllocClass Hash:VALUE(0x1008)
          IncrCounter complex_arg_pass_param_block
          v19:BasicObject = Send v46, :initialize # SendFallbackReason: Complex argument passing
          CheckInterrupts
          CheckInterrupts
          Return v46
        ");
        assert_snapshot!(inspect("test"), @"{}");
    }

    #[test]
    fn test_opt_new_array() {
        eval("
            def test = Array.new 1
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Array)
          v46:Class[Array@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1008, new@0x1009, cme:0x1010)
          PatchPoint NoSingletonClass(Class@0x1038)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v57:BasicObject = CCallVariadic v46, :Array.new@0x1040, v15
          CheckInterrupts
          Return v57
        ");
    }

    #[test]
    fn test_opt_new_set() {
        eval("
            def test = Set.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Set)
          v43:Class[Set@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Set@0x1008, new@0x1009, cme:0x1010)
          v17:HeapBasicObject = ObjectAlloc v43
          PatchPoint NoSingletonClass(Set@0x1008)
          PatchPoint MethodRedefined(Set@0x1008, initialize@0x1038, cme:0x1040)
          v49:SetExact = GuardType v17, SetExact
          v50:BasicObject = CCallVariadic v49, :Set#initialize@0x1068
          CheckInterrupts
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_opt_new_string() {
        eval("
            def test = String.new
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v43:Class[String@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(String@0x1008, new@0x1009, cme:0x1010)
          PatchPoint NoSingletonClass(Class@0x1038)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v54:BasicObject = CCallVariadic v43, :String.new@0x1040
          CheckInterrupts
          Return v54
        ");
    }

    #[test]
    fn test_opt_new_regexp() {
        eval("
            def test = Regexp.new ''
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Regexp)
          v47:Class[Regexp@0x1008] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v15:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v16:StringExact = StringCopy v15
          PatchPoint MethodRedefined(Regexp@0x1008, new@0x1018, cme:0x1020)
          v50:RegexpExact = ObjectAllocClass Regexp:VALUE(0x1008)
          PatchPoint NoSingletonClass(Regexp@0x1008)
          PatchPoint MethodRedefined(Regexp@0x1008, initialize@0x1048, cme:0x1050)
          v54:BasicObject = CCallVariadic v50, :Regexp#initialize@0x1078, v16
          CheckInterrupts
          CheckInterrupts
          Return v50
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
          IncrCounter inline_cfunc_optimized_send_count
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
          IncrCounter inline_cfunc_optimized_send_count
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
          v15:CPtr = GetEP 0
          v16:CInt64 = LoadField v15, :_env_data_index_flags@0x1001
          v17:CInt64 = GuardNoBitsSet v16, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v18:CInt64 = LoadField v15, :_env_data_index_specval@0x1002
          v19:CInt64 = GuardAnyBitSet v18, CUInt64(1)
          v20:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          v22:BasicObject = Send v9, 0x1001, :tap, v20 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v22
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
          v27:BasicObject = GetBlockParam :block, l0, EP@3
          Jump bb6(v9, v27, v27)
        bb4(v16:BasicObject, v17:BasicObject):
          v24:CPtr = GetEP 0
          v25:BasicObject = LoadField v24, :block@0x1001
          Jump bb6(v16, v25, v25)
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
          v21:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb6(v6, v21)
        bb4(v12:BasicObject):
          v18:CPtr = GetEP 1
          v19:BasicObject = LoadField v18, :block@0x1000
          Jump bb6(v12, v19)
        bb6(v23:BasicObject, v24:BasicObject):
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
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
          PatchPoint SingleRactorMode
          IncrCounter getivar_fallback_not_monomorphic
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
          IncrCounter setivar_fallback_not_monomorphic
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
          v16:HeapBasicObject = GuardType v6, HeapBasicObject
          v17:CShape = LoadField v16, :_shape_id@0x1000
          v18:CShape[0x1001] = GuardBitEquals v17, CShape(0x1001)
          v19:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_specialize_monomorphic_definedivar_false() {
        eval("
            def test = defined?(@foo)
            test
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
          v16:HeapBasicObject = GuardType v6, HeapBasicObject
          v17:CShape = LoadField v16, :_shape_id@0x1000
          v18:CShape[0x1001] = GuardBitEquals v17, CShape(0x1001)
          v19:NilClass = Const Value(nil)
          CheckInterrupts
          Return v19
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
          v25:HeapObject[class_exact:Proc] = GuardType v10, HeapObject[class_exact:Proc]
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
          v26:HeapObject[class_exact:Proc] = GuardType v10, HeapObject[class_exact:Proc]
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
          v25:HeapObject[class_exact:Proc] = GuardType v10, HeapObject[class_exact:Proc]
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
          v25:HeapObject[class_exact:Proc] = GuardType v10, HeapObject[class_exact:Proc]
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
          IncrCounter complex_arg_pass_caller_splat
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
          IncrCounter complex_arg_pass_caller_kwarg
          v17:BasicObject = Send v10, :call, v15 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_dont_specialize_definedivar_with_t_data() {
        eval("
            class C < Range
              def test = defined?(@a)
            end
            obj = C.new 0, 1
            obj.instance_variable_set(:@a, 1)
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
          IncrCounter definedivar_fallback_not_t_object
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_polymorphic_definedivar() {
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
          IncrCounter definedivar_fallback_not_monomorphic
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          CheckInterrupts
          Return v10
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
          IncrCounter definedivar_fallback_too_complex
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v21:HeapBasicObject = GuardType v6, HeapBasicObject
          v22:CShape = LoadField v21, :_shape_id@0x1000
          v23:CShape[0x1001] = GuardBitEquals v22, CShape(0x1001)
          StoreField v21, :@foo@0x1002, v10
          WriteBarrier v21, v10
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v21:HeapBasicObject = GuardType v6, HeapBasicObject
          v22:CShape = LoadField v21, :_shape_id@0x1000
          v23:CShape[0x1001] = GuardBitEquals v22, CShape(0x1001)
          StoreField v21, :@foo@0x1002, v10
          WriteBarrier v21, v10
          v26:CShape[0x1003] = Const CShape(0x1003)
          StoreField v21, :_shape_id@0x1000, v26
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_specialize_multiple_monomorphic_setivar_with_shape_transition() {
        eval("
            def test
              @foo = 1
              @bar = 2
            end
            test
        ");
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          v28:HeapBasicObject = GuardType v6, HeapBasicObject
          v29:CShape = LoadField v28, :_shape_id@0x1000
          v30:CShape[0x1001] = GuardBitEquals v29, CShape(0x1001)
          StoreField v28, :@foo@0x1002, v10
          WriteBarrier v28, v10
          v33:CShape[0x1003] = Const CShape(0x1003)
          StoreField v28, :_shape_id@0x1000, v33
          v14:HeapBasicObject = RefineType v6, HeapBasicObject
          v17:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          v36:CShape = LoadField v14, :_shape_id@0x1000
          v37:CShape[0x1003] = GuardBitEquals v36, CShape(0x1003)
          StoreField v14, :@bar@0x1004, v17
          WriteBarrier v14, v17
          v40:CShape[0x1005] = Const CShape(0x1005)
          StoreField v14, :_shape_id@0x1000, v40
          CheckInterrupts
          Return v17
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_not_t_object
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_not_monomorphic
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_too_complex
          SetIvar v6, :@a, v10
          CheckInterrupts
          Return v10
        ");
    }

    #[test]
    fn test_dont_specialize_setivar_when_next_shape_is_too_complex() {
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_new_shape_too_complex
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
    fn test_dont_optimize_hash_freeze_if_redefined() {
        eval("
            class Hash
              def freeze; end
            end
            def test = {}.freeze
        ");
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
    fn test_elide_freeze_with_refrozen_hash() {
        eval("
            def test = {}.freeze.freeze
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
          v10:HashExact = NewHash
          v12:NilClass = Const Value(nil)
          v14:BasicObject = Send v10, :freeze, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_elide_freeze_with_frozen_ary() {
        eval("
            def test = [].freeze
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
    fn test_no_elide_freeze_with_unfrozen_ary() {
        eval("
            def test = [].dup.freeze
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
          v10:ArrayExact = NewArray
          v12:NilClass = Const Value(nil)
          v14:BasicObject = Send v10, :freeze, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_elide_freeze_with_frozen_str() {
        eval("
            def test = ''.freeze
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
    fn test_no_elide_freeze_with_unfrozen_str() {
        eval("
            def test = ''.dup.freeze
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
          v11:StringExact = StringCopy v10
          v13:NilClass = Const Value(nil)
          v15:BasicObject = Send v11, :freeze, v13 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_elide_uminus_with_frozen_str() {
        eval("
            def test = -''
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
          v13:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v14:StringExact = StringCopy v13
          v21:StringExact = StringConcat v10, v14
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_objtostring_anytostring_with_non_string() {
        eval(r##"
            def test = "#{1}"
        "##);
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
          v29:String = GuardType v10, String
          v22:StringExact = StringConcat v14, v29
          CheckInterrupts
          Return v22
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
          v29:String = GuardType v10, String
          v22:StringExact = StringConcat v14, v29
          CheckInterrupts
          Return v22
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
          v28:ArrayExact = GuardType v10, ArrayExact
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, to_s@0x1018, cme:0x1020)
          v33:BasicObject = CCallWithFrame v28, :Array#to_s@0x1048
          v20:String = AnyToString v10, str: v33
          v22:StringExact = StringConcat v14, v20
          CheckInterrupts
          Return v22
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
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          v21:NilClass = Const Value(nil)
          CheckInterrupts
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
          v23:Fixnum[1] = RefineType v13, NotNil
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_eliminate_load_from_non_frozen_array() {
        eval(r##"
            S = [4,5,6]
            def test = S[0]
            test
        "##);
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, S)
          v23:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, []@0x1018, cme:0x1020)
          v27:CInt64[0] = UnboxFixnum v12
          v28:CInt64 = ArrayLength v23
          v29:CInt64[0] = GuardLess v27, v28
          v30:CInt64[0] = Const CInt64(0)
          v31:CInt64[0] = GuardGreaterEq v29, v30
          v32:BasicObject = ArrayAref v23, v31
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v32
        ");
       // TODO(max): Check the result of `S[0] = 5; test` using `inspect` to make sure that we
       // actually do the load at run-time.
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_in_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[1]
        "##);
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
          v13:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v25:CInt64[1] = UnboxFixnum v13
          v26:CInt64 = ArrayLength v11
          v27:CInt64[1] = GuardLess v25, v26
          v28:CInt64[0] = Const CInt64(0)
          v29:CInt64[1] = GuardGreaterEq v27, v28
          v32:Fixnum[5] = Const Value(5)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative() {
        eval(r##"
            def test = [4,5,6].freeze[-3]
        "##);
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
          v13:Fixnum[-3] = Const Value(-3)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v25:CInt64[-3] = UnboxFixnum v13
          v26:CInt64 = ArrayLength v11
          v27:CInt64[-3] = GuardLess v25, v26
          v28:CInt64[0] = Const CInt64(0)
          v29:CInt64[-3] = GuardGreaterEq v27, v28
          v32:Fixnum[4] = Const Value(4)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[-10]
        "##);
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
          v13:Fixnum[-10] = Const Value(-10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v25:CInt64[-10] = UnboxFixnum v13
          v26:CInt64 = ArrayLength v11
          v27:CInt64[-10] = GuardLess v25, v26
          v28:CInt64[0] = Const CInt64(0)
          v29:CInt64[-10] = GuardGreaterEq v27, v28
          v32:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[10]
        "##);
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
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v25:CInt64[10] = UnboxFixnum v13
          v26:CInt64 = ArrayLength v11
          v27:CInt64[10] = GuardLess v25, v26
          v28:CInt64[0] = Const CInt64(0)
          v29:CInt64[10] = GuardGreaterEq v27, v28
          v32:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v32
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
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v24:BasicObject = SendDirect v11, 0x1040, :[] (0x1050), v13
          CheckInterrupts
          Return v24
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
          v23:BasicObject = Send v10, :[]=, v17, v19 # SendFallbackReason: Uncategorized(opt_aset)
          CheckInterrupts
          Return v19
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
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:ArrayExact = ArrayDup v10
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, max@0x1010, cme:0x1018)
          v21:BasicObject = SendDirect v11, 0x1040, :max (0x1050)
          CheckInterrupts
          Return v21
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
        assert_snapshot!(hir_string("test"), @r"
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
          v18:SetExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v18
        ");
    }

    #[test]
    fn test_regexp_type() {
        eval("
            def test = /a/
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
          PatchPoint SingleRactorMode
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, zero@0x1008, cme:0x1010)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v31:StaticSymbol[:b] = Const Value(VALUE(0x1038))
          PatchPoint MethodRedefined(Object@0x1000, one@0x1040, cme:0x1048)
          v28:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_symbol_block_bmethod() {
        eval("
            define_method(:identity, &:itself)
            def test = identity(100)
            test
        ");
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
        assert_snapshot!(hir_string("test"), @r"
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
          v22:Class[Foo@0x1008] = Const Value(VALUE(0x1008))
          v12:Fixnum[100] = Const Value(100)
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, identity@0x1018, cme:0x1020)
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_nil_nil_specialized_to_ccall() {
        eval("
            def test = nil.nil?
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
          v10:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v21:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v21:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:NilClass = GuardType v10, NilClass
          v25:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:FalseClass = GuardType v10, FalseClass
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:TrueClass = GuardType v10, TrueClass
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:StaticSymbol = GuardType v10, StaticSymbol
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:Fixnum = GuardType v10, Fixnum
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:Flonum = GuardType v10, Flonum
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:StringExact = GuardType v10, StringExact
          v26:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:ArrayExact = GuardType v10, ArrayExact
          v26:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:FalseClass = GuardType v10, FalseClass
          v25:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:NilClass = GuardType v10, NilClass
          v25:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          IfFalse v16, bb4(v9, v17)
          v19:Truthy = RefineType v10, Truthy
          v21:FalseClass = Const Value(false)
          CheckInterrupts
          Jump bb5(v9, v19, v21)
        bb4(v25:BasicObject, v26:Falsy):
          v29:NilClass = Const Value(nil)
          Jump bb5(v25, v26, v29)
        bb5(v31:BasicObject, v32:BasicObject, v33:Falsy):
          PatchPoint MethodRedefined(NilClass@0x1008, !@0x1010, cme:0x1018)
          v45:NilClass = GuardType v33, NilClass
          v46:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v46
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
          v25:ArrayExact = GuardType v10, ArrayExact
          v26:CInt64 = ArrayLength v25
          v27:CInt64[0] = Const CInt64(0)
          v28:CBool = IsBitEqual v26, v27
          v29:BoolExact = BoxBool v28
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:HashExact = GuardType v10, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall v25, :Hash#empty?@0x1040
          CheckInterrupts
          Return v27
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
          v29:HeapObject[class_exact:C] = GuardType v12, HeapObject[class_exact:C]
          v30:CBool = IsBitEqual v29, v13
          v31:BoolExact = BoxBool v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:Fixnum = GuardType v12, Fixnum
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumAnd v28, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:Fixnum = GuardType v12, Fixnum
          v29:Fixnum = GuardType v13, Fixnum
          v30:Fixnum = FixnumOr v28, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:NilClass = Const Value(nil)
          CheckInterrupts
          Return v22
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v26:CShape = LoadField v23, :_shape_id@0x1040
          v27:CShape[0x1041] = GuardBitEquals v26, CShape(0x1041)
          v28:BasicObject = LoadField v23, :@foo@0x1042
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_getivar_extended() {
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v26:CShape = LoadField v23, :_shape_id@0x1040
          v27:CShape[0x1041] = GuardBitEquals v26, CShape(0x1041)
          v28:CPtr = LoadField v23, :_as_heap@0x1042
          v29:BasicObject = LoadField v28, :@foo@0x1043
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_optimize_getivar_on_module() {
        eval("
            module M
              @foo = 42
              def self.test = @foo
            end
            M.test
        ");
        assert_snapshot!(hir_string_proc("M.method(:test)"), @r"
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
          v17:HeapBasicObject = GuardType v6, HeapBasicObject
          v18:CShape = LoadField v17, :_shape_id@0x1000
          v19:CShape[0x1001] = GuardBitEquals v18, CShape(0x1001)
          v20:CUInt16[0] = Const CUInt16(0)
          v21:BasicObject = CCall v17, :rb_ivar_get_at_no_ractor_check@0x1008, v20
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_optimize_getivar_on_class() {
        eval("
            class C
              @foo = 42
              def self.test = @foo
            end
            C.test
        ");
        assert_snapshot!(hir_string_proc("C.method(:test)"), @r"
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
          v17:HeapBasicObject = GuardType v6, HeapBasicObject
          v18:CShape = LoadField v17, :_shape_id@0x1000
          v19:CShape[0x1001] = GuardBitEquals v18, CShape(0x1001)
          v20:CUInt16[0] = Const CUInt16(0)
          v21:BasicObject = CCall v17, :rb_ivar_get_at_no_ractor_check@0x1008, v20
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_optimize_getivar_on_t_data() {
        eval("
            class C < Range
              def test = @a
            end
            obj = C.new 0, 1
            obj.instance_variable_set(:@a, 1)
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
          PatchPoint SingleRactorMode
          v17:HeapBasicObject = GuardType v6, HeapBasicObject
          v18:CShape = LoadField v17, :_shape_id@0x1000
          v19:CShape[0x1001] = GuardBitEquals v18, CShape(0x1001)
          v20:CUInt16[0] = Const CUInt16(0)
          v21:BasicObject = CCall v17, :rb_ivar_get_at_no_ractor_check@0x1008, v20
          CheckInterrupts
          Return v21
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
        assert_snapshot!(hir_string_proc("M.method(:test)"), @r"
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
        assert_snapshot!(hir_string_proc("M.method(:test)"), @r"
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
          v11:BasicObject = Send v6, :foo # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_dont_optimize_getivar_polymorphic() {
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
          v15:CBool = HasType v10, HeapObject[class_exact:C]
          IfTrue v15, bb5(v9, v10, v10)
          v24:CBool = HasType v10, HeapObject[class_exact:C]
          IfTrue v24, bb6(v9, v10, v10)
          v33:BasicObject = Send v10, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v9, v10, v33)
        bb5(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          v20:HeapObject[class_exact:C] = RefineType v18, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          IncrCounter getivar_fallback_not_monomorphic
          v46:BasicObject = GetIvar v20, :@foo
          Jump bb4(v16, v17, v46)
        bb6(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          v29:HeapObject[class_exact:C] = RefineType v27, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          IncrCounter getivar_fallback_not_monomorphic
          v49:BasicObject = GetIvar v29, :@foo
          Jump bb4(v25, v26, v49)
        bb4(v35:BasicObject, v36:BasicObject, v37:BasicObject):
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn test_dont_optimize_getivar_with_too_complex_shape() {
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          IncrCounter getivar_fallback_too_complex
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
          v36:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint StableConstantNames(0x1010, B)
          v39:ArrayExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          PatchPoint NoSingletonClass(Array@0x1020)
          PatchPoint MethodRedefined(Array@0x1020, zip@0x1028, cme:0x1030)
          v43:BasicObject = CCallVariadic v36, :zip@0x1058, v39
          v22:CPtr = GetEP 0
          v23:BasicObject = LoadField v22, :result@0x1060
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v16:CPtr = GetEP 0
          v17:CInt64 = LoadField v16, :_env_data_index_flags@0x1001
          v18:CInt64 = GuardNoBitsSet v17, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v19:CInt64 = LoadField v16, :_env_data_index_specval@0x1002
          v20:CInt64 = GuardAnyBitSet v19, CUInt64(1)
          v21:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          IncrCounter complex_arg_pass_caller_blockarg
          v23:BasicObject = Send v14, 0x1001, :map, v21 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v23
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
          v16:CPtr = GetEP 0
          v17:CInt64 = LoadField v16, :_env_data_index_flags@0x1001
          v18:CInt64 = GuardNoBitsSet v17, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v19:CInt64 = LoadField v16, :_env_data_index_specval@0x1002
          v20:CInt64[0] = GuardBitEquals v19, CInt64(0)
          v21:NilClass = Const Value(nil)
          IncrCounter complex_arg_pass_caller_blockarg
          v23:BasicObject = Send v14, 0x1001, :map, v21 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v23
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
        assert_snapshot!(hir_string_proc("test"), @r"
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
          v12:CPtr = GetEP 1
          v13:CInt64 = LoadField v12, :_env_data_index_flags@0x1000
          v14:CInt64 = GuardNoBitsSet v13, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v15:CInt64 = LoadField v12, :_env_data_index_specval@0x1001
          v16:CInt64 = GuardAnyBitSet v15, CUInt64(1)
          v17:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          IncrCounter complex_arg_pass_caller_blockarg
          v19:BasicObject = Send v10, 0x1000, :map, v17 # SendFallbackReason: Complex argument passing
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_send_direct_iseq_with_block_no_callee_block_param() {
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendDirect v20, 0x1038, :foo (0x1048)
          CheckInterrupts
          Return v21
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v25:CShape = LoadField v20, :_shape_id@0x1048
          v26:CShape[0x1049] = GuardBitEquals v25, CShape(0x1049)
          v27:NilClass = Const Value(nil)
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v25:CShape = LoadField v20, :_shape_id@0x1048
          v26:CShape[0x1049] = GuardBitEquals v25, CShape(0x1049)
          v27:NilClass = Const Value(nil)
          CheckInterrupts
          Return v27
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v26:CShape = LoadField v23, :_shape_id@0x1040
          v27:CShape[0x1041] = GuardBitEquals v26, CShape(0x1041)
          v28:NilClass = Const Value(nil)
          CheckInterrupts
          Return v28
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v26:CShape = LoadField v23, :_shape_id@0x1040
          v27:CShape[0x1041] = GuardBitEquals v26, CShape(0x1041)
          v28:NilClass = Const Value(nil)
          CheckInterrupts
          Return v28
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v31:CShape = LoadField v28, :_shape_id@0x1040
          v32:CShape[0x1041] = GuardBitEquals v31, CShape(0x1041)
          StoreField v28, :@foo@0x1042, v17
          WriteBarrier v28, v17
          v35:CShape[0x1043] = Const CShape(0x1043)
          StoreField v28, :_shape_id@0x1040, v35
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v31:CShape = LoadField v28, :_shape_id@0x1040
          v32:CShape[0x1041] = GuardBitEquals v31, CShape(0x1041)
          StoreField v28, :@foo@0x1042, v17
          WriteBarrier v28, v17
          v35:CShape[0x1043] = Const CShape(0x1043)
          StoreField v28, :_shape_id@0x1040, v35
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          v24:CPtr = LoadField v23, :_as_heap@0x1040
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
          v27:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
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
          v31:HeapObject[class_exact:C] = GuardType v12, HeapObject[class_exact:C]
          v32:CUInt64 = LoadField v31, :_rbasic_flags@0x1040
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
          v31:HeapObject[class_exact:C] = GuardType v12, HeapObject[class_exact:C]
          v32:CUInt64 = LoadField v31, :_rbasic_flags@0x1040
          v33:CUInt64 = GuardNoBitsSet v32, RUBY_FL_FREEZE=CUInt64(2048)
          v34:CPtr = LoadField v31, :_as_heap@0x1041
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
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v11
        ");
    }

    #[test]
    fn test_inline_string_literal_to_s() {
        eval(r#"
            def test = "foo".to_s
        "#);
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
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
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
          v23:Fixnum = GuardType v10, Fixnum
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
          v23:Integer = GuardType v10, Integer
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
          v28:Fixnum = GuardType v10, Fixnum
          PatchPoint MethodRedefined(Integer@0x1010, to_s@0x1018, cme:0x1020)
          v32:StringExact = CCallVariadic v28, :Integer#to_s@0x1048
          v22:StringExact = StringConcat v14, v32
          CheckInterrupts
          Return v22
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
          v13:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:ArrayExact = ArrayDup v13
          v19:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v31:CInt64[0] = UnboxFixnum v19
          v32:CInt64 = ArrayLength v14
          v33:CInt64[0] = GuardLess v31, v32
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64[0] = GuardGreaterEq v33, v34
          v36:BasicObject = ArrayAref v14, v35
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v36
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
          v29:ArrayExact = GuardType v12, ArrayExact
          v30:Fixnum = GuardType v13, Fixnum
          v31:CInt64 = UnboxFixnum v30
          v32:CInt64 = ArrayLength v29
          v33:CInt64 = GuardLess v31, v32
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64 = GuardGreaterEq v33, v34
          v36:BasicObject = ArrayAref v29, v35
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v36
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
          v29:ArraySubclass[class_exact:C] = GuardType v12, ArraySubclass[class_exact:C]
          v30:Fixnum = GuardType v13, Fixnum
          v31:CInt64 = UnboxFixnum v30
          v32:CInt64 = ArrayLength v29
          v33:CInt64 = GuardLess v31, v32
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64 = GuardGreaterEq v33, v34
          v36:BasicObject = ArrayAref v29, v35
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v36
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
          v13:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:HashExact = HashDup v13
          v19:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          v31:BasicObject = HashAref v14, v19
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:HashExact = GuardType v12, HashExact
          v30:BasicObject = HashAref v29, v13
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:HashSubclass[class_exact:C] = GuardType v12, HashSubclass[class_exact:C]
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, H)
          v23:HashExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:StaticSymbol[:a] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(Hash@0x1018)
          PatchPoint MethodRedefined(Hash@0x1018, []@0x1020, cme:0x1028)
          v27:BasicObject = HashAref v23, v12
          IncrCounter inline_cfunc_optimized_send_count
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
          v13:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v22:Fixnum[1] = Const Value(1)
          v24:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []=@0x1008, cme:0x1010)
          HashAset v13, v22, v24
          IncrCounter inline_cfunc_optimized_send_count
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
          v37:HashExact = GuardType v14, HashExact
          HashAset v37, v15, v16
          IncrCounter inline_cfunc_optimized_send_count
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
          v37:HashSubclass[class_exact:C] = GuardType v14, HashSubclass[class_exact:C]
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
          PatchPoint StableConstantNames(0x1000, Thread)
          v20:Class[Thread@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, current@0x1018, cme:0x1020)
          v24:CPtr = LoadEC
          v25:CPtr = LoadField v24, :thread_ptr@0x1048
          v26:BasicObject = LoadField v25, :self@0x1049
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v33:ArrayExact = GuardType v10, ArrayExact
          v34:CUInt64 = LoadField v33, :_rbasic_flags@0x1040
          v35:CUInt64 = GuardNoBitsSet v34, RUBY_FL_FREEZE=CUInt64(2048)
          v36:CUInt64 = LoadField v33, :_rbasic_flags@0x1040
          v37:CUInt64 = GuardNoBitsSet v36, RUBY_ELTS_SHARED=CUInt64(4096)
          v38:CInt64[1] = UnboxFixnum v17
          v39:CInt64 = ArrayLength v33
          v40:CInt64[1] = GuardLess v38, v39
          v41:CInt64[0] = Const CInt64(0)
          v42:CInt64[1] = GuardGreaterEq v40, v41
          ArrayAset v33, v42, v19
          WriteBarrier v33, v19
          IncrCounter inline_cfunc_optimized_send_count
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
          v37:ArrayExact = GuardType v14, ArrayExact
          v38:Fixnum = GuardType v15, Fixnum
          v39:CUInt64 = LoadField v37, :_rbasic_flags@0x1040
          v40:CUInt64 = GuardNoBitsSet v39, RUBY_FL_FREEZE=CUInt64(2048)
          v41:CUInt64 = LoadField v37, :_rbasic_flags@0x1040
          v42:CUInt64 = GuardNoBitsSet v41, RUBY_ELTS_SHARED=CUInt64(4096)
          v43:CInt64 = UnboxFixnum v38
          v44:CInt64 = ArrayLength v37
          v45:CInt64 = GuardLess v43, v44
          v46:CInt64[0] = Const CInt64(0)
          v47:CInt64 = GuardGreaterEq v45, v46
          ArrayAset v37, v47, v16
          WriteBarrier v37, v16
          IncrCounter inline_cfunc_optimized_send_count
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
          v37:ArraySubclass[class_exact:MyArray] = GuardType v14, ArraySubclass[class_exact:MyArray]
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
          v27:ArrayExact = GuardType v10, ArrayExact
          ArrayPush v27, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:ArrayExact = GuardType v10, ArrayExact
          ArrayPush v26, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v30:ArrayExact = GuardType v10, ArrayExact
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
        assert_snapshot!(hir_string_proc("PushSubArray.new.method(:<<)"), @r"
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
          v24:RubyValue = LoadField v23, :_ep_method_entry@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :_ep_specval@0x1050
          v27:FalseClass = GuardBitEquals v26, Value(false)
          v28:Array = GuardType v9, Array
          ArrayPush v28, v10
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string_proc("PopSubArray.new.method(:pop)"), @r"
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
          v19:RubyValue = LoadField v18, :_ep_method_entry@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :_ep_specval@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v28:CPtr = GetEP 0
          v29:RubyValue = LoadField v28, :_ep_method_entry@0x1038
          v30:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v29, Value(VALUE(0x1040))
          v31:RubyValue = LoadField v28, :_ep_specval@0x1048
          v32:FalseClass = GuardBitEquals v31, Value(false)
          v23:Array = GuardType v6, Array
          v24:CUInt64 = LoadField v23, :_rbasic_flags@0x1049
          v25:CUInt64 = GuardNoBitsSet v24, RUBY_ELTS_SHARED=CUInt64(4096)
          v26:BasicObject = ArrayPop v23
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string_proc("ArefSubArray.new.method(:[])"), @r"
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
          v24:RubyValue = LoadField v23, :_ep_method_entry@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :_ep_specval@0x1050
          v27:FalseClass = GuardBitEquals v26, Value(false)
          v37:CPtr = GetEP 0
          v38:RubyValue = LoadField v37, :_ep_method_entry@0x1040
          v39:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v38, Value(VALUE(0x1048))
          v40:RubyValue = LoadField v37, :_ep_specval@0x1050
          v41:FalseClass = GuardBitEquals v40, Value(false)
          v28:Array = GuardType v9, Array
          v29:Fixnum = GuardType v10, Fixnum
          v30:CInt64 = UnboxFixnum v29
          v31:CInt64 = ArrayLength v28
          v32:CInt64 = GuardLess v30, v31
          v33:CInt64[0] = Const CInt64(0)
          v34:CInt64 = GuardGreaterEq v32, v33
          v35:BasicObject = ArrayAref v28, v34
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v35
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
        assert_snapshot!(hir_string_proc("ArefSubArrayRange.new.method(:[])"), @r"
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
          v24:RubyValue = LoadField v23, :_ep_method_entry@0x1040
          v25:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v24, Value(VALUE(0x1048))
          v26:RubyValue = LoadField v23, :_ep_specval@0x1050
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
          v25:ArrayExact = GuardType v10, ArrayExact
          v26:CInt64 = ArrayLength v25
          v27:Fixnum = BoxFixnum v26
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:ArrayExact = GuardType v10, ArrayExact
          v26:CInt64 = ArrayLength v25
          v27:Fixnum = BoxFixnum v26
          IncrCounter inline_cfunc_optimized_send_count
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
          v27:StringExact = GuardType v10, StringExact
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
          v28:StringExact = GuardType v12, StringExact
          v29:Fixnum = GuardType v13, Fixnum
          v30:CInt64 = UnboxFixnum v29
          v31:CInt64 = LoadField v28, :len@0x1040
          v32:CInt64 = GuardLess v30, v31
          v33:CInt64[0] = Const CInt64(0)
          v34:CInt64 = GuardGreaterEq v32, v33
          v35:Fixnum = StringGetbyte v28, v32
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v35
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
          v32:StringExact = GuardType v12, StringExact
          v33:Fixnum = GuardType v13, Fixnum
          v34:CInt64 = UnboxFixnum v33
          v35:CInt64 = LoadField v32, :len@0x1040
          v36:CInt64 = GuardLess v34, v35
          v37:CInt64[0] = Const CInt64(0)
          v38:CInt64 = GuardGreaterEq v36, v37
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:StringExact = GuardType v14, StringExact
          v33:Fixnum = GuardType v15, Fixnum
          v34:Fixnum = GuardType v16, Fixnum
          v35:CInt64 = UnboxFixnum v33
          v36:CInt64 = LoadField v32, :len@0x1040
          v37:CInt64 = GuardLess v35, v36
          v38:CInt64[0] = Const CInt64(0)
          v39:CInt64 = GuardGreaterEq v37, v38
          v40:CUInt64 = LoadField v32, :_rbasic_flags@0x1041
          v41:CUInt64 = GuardNoBitsSet v40, RUBY_FL_FREEZE=CUInt64(2048)
          v42:Fixnum = StringSetbyteFixnum v32, v33, v34
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:StringSubclass[class_exact:MyString] = GuardType v14, StringSubclass[class_exact:MyString]
          v33:Fixnum = GuardType v15, Fixnum
          v34:Fixnum = GuardType v16, Fixnum
          v35:CInt64 = UnboxFixnum v33
          v36:CInt64 = LoadField v32, :len@0x1040
          v37:CInt64 = GuardLess v35, v36
          v38:CInt64[0] = Const CInt64(0)
          v39:CInt64 = GuardGreaterEq v37, v38
          v40:CUInt64 = LoadField v32, :_rbasic_flags@0x1041
          v41:CUInt64 = GuardNoBitsSet v40, RUBY_FL_FREEZE=CUInt64(2048)
          v42:Fixnum = StringSetbyteFixnum v32, v33, v34
          IncrCounter inline_cfunc_optimized_send_count
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
          v32:StringExact = GuardType v14, StringExact
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
          v25:StringExact = GuardType v10, StringExact
          v26:CInt64 = LoadField v25, :len@0x1040
          v27:CInt64[0] = Const CInt64(0)
          v28:CBool = IsBitEqual v26, v27
          v29:BoolExact = BoxBool v28
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:Fixnum = GuardType v10, Fixnum
          v25:Fixnum[1] = Const Value(1)
          v26:Fixnum = FixnumAdd v24, v25
          IncrCounter inline_cfunc_optimized_send_count
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
          v24:Integer = GuardType v10, Integer
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
          v26:Fixnum = GuardType v10, Fixnum
          v27:Fixnum = FixnumLShift v26, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:Fixnum = GuardType v10, Fixnum
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
          v26:Fixnum = GuardType v10, Fixnum
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
          v28:Fixnum = GuardType v12, Fixnum
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
          v25:Fixnum = GuardType v10, Fixnum
          v26:Fixnum = FixnumRShift v25, v15
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:Fixnum = GuardType v10, Fixnum
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
          v25:Fixnum = GuardType v10, Fixnum
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
          v27:Fixnum = GuardType v12, Fixnum
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
          v29:StringExact = GuardType v12, StringExact
          v30:String = GuardType v13, String
          v31:StringExact = StringAppend v29, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringExact = GuardType v12, StringExact
          v30:Fixnum = GuardType v13, Fixnum
          v31:StringExact = StringAppendCodepoint v29, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringExact = GuardType v12, StringExact
          v30:String = GuardType v13, String
          v31:StringExact = StringAppend v29, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringSubclass[class_exact:MyString] = GuardType v12, StringSubclass[class_exact:MyString]
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
          v24:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v26:BoolExact = CCall v24, :String#ascii_only?@0x1040
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_optimize_when_passing_too_few_args() {
        eval(r#"
            public def foo(lead, opt=raise) = opt
            def test = 0.foo
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
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[1] = Const Value(1)
          v14:BasicObject = Send v10, :succ, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
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
          v27:Fixnum = GuardType v12, Fixnum
          v28:Fixnum = GuardType v13, Fixnum
          v29:Fixnum = FixnumXor v27, v28
          IncrCounter inline_cfunc_optimized_send_count
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
          v31:Fixnum = GuardType v12, Fixnum
          v32:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v23:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_bignum_or_boolean() {
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
          v27:Integer = GuardType v12, Integer
          v28:BasicObject = CCallWithFrame v27, :Integer#^@0x1040, v13
          CheckInterrupts
          Return v28
        ");

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
          v27:Fixnum = GuardType v12, Fixnum
          v28:BasicObject = CCallWithFrame v27, :Integer#^@0x1040, v13
          CheckInterrupts
          Return v28
        ");

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
          v27:TrueClass = GuardType v12, TrueClass
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
          v18:BasicObject = Send v12, :^ # SendFallbackReason: Uncategorized(opt_send_without_block)
          CheckInterrupts
          Return v18
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
          v25:HashExact = GuardType v10, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall v25, :Hash#size@0x1040
          CheckInterrupts
          Return v27
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
          v29:HashExact = GuardType v10, HashExact
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v30:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, respond_to_missing?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1078, cme:0x1080)
          v32:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v30:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, foo@0x1048, cme:0x1050)
          v32:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1010, respond_to_missing?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1078, cme:0x1080)
          v32:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
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
          v26:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v19
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
        assert_snapshot!(hir_string("test"), @r"
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:StringExact[VALUE(0x1038)] = Const Value(VALUE(0x1038))
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putnil() {
        eval(r#"
            def callee = nil
            def test = callee
            test
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:NilClass = Const Value(nil)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_true() {
        eval(r#"
            def callee = true
            def test = callee
            test
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:TrueClass = Const Value(true)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_false() {
        eval(r#"
            def callee = false
            def test = callee
            test
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:FalseClass = Const Value(false)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_zero() {
        eval(r#"
            def callee = 0
            def test = callee
            test
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_putobject_one() {
        eval(r#"
            def callee = 1
            def test = callee
            test
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v22:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_without_block_direct_parameter() {
        eval(r#"
            def callee(x) = x
            def test = callee 3
            test
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v25:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
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
        assert_snapshot!(hir_string("test"), @r"
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
          IncrCounter complex_arg_pass_caller_splat
          v21:BasicObject = Send v8, :foo, v19 # SendFallbackReason: Complex argument passing
          v25:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v26:StringExact = StringCopy v25
          PatchPoint NoEPEscape(test)
          v31:ArrayExact = ToArray v13
          IncrCounter complex_arg_pass_caller_splat
          v33:BasicObject = Send v26, :display, v31 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          v41:ArrayExact = ToArray v13
          IncrCounter complex_arg_pass_caller_splat
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
          v22:StaticSymbol = GuardType v10, StaticSymbol
          IncrCounter inline_iseq_optimized_send_count
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
          v22:Fixnum = GuardType v10, Fixnum
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_no_params() {
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_one_param() {
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_inline_send_with_block_with_multiple_params() {
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          CheckInterrupts
          Return v23
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
          v11:StaticSymbol[:the_block] = Const Value(VALUE(0x1000))
          v13:BasicObject = Send v6, 0x1008, :callee, v11 # SendFallbackReason: Uncategorized(send)
          CheckInterrupts
          Return v13
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
          v29:StringExact = GuardType v12, StringExact
          v30:String = GuardType v13, String
          v31:BoolExact = CCall v29, :String#==@0x1040, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringSubclass[class_exact:C] = GuardType v12, StringSubclass[class_exact:C]
          v30:String = GuardType v13, String
          v31:BoolExact = CCall v29, :String#==@0x1040, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v29:StringExact = GuardType v12, StringExact
          v30:String = GuardType v13, String
          v31:BoolExact = CCall v29, :String#==@0x1040, v30
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:StringExact = GuardType v12, StringExact
          v29:String = GuardType v13, String
          v30:BoolExact = CCall v28, :String#==@0x1040, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:StringSubclass[class_exact:C] = GuardType v12, StringSubclass[class_exact:C]
          v29:String = GuardType v13, String
          v30:BoolExact = CCall v28, :String#==@0x1040, v29
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:StringExact = GuardType v12, StringExact
          v29:String = GuardType v13, String
          v30:BoolExact = CCall v28, :String#==@0x1040, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
          v25:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall v25, :String#size@0x1040
          CheckInterrupts
          Return v27
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
         v29:StringExact = GuardType v10, StringExact
         IncrCounter inline_cfunc_optimized_send_count
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
          v24:StringExact = GuardType v10, StringExact
          v25:CInt64 = LoadField v24, :len@0x1040
          v26:Fixnum = BoxFixnum v25
          IncrCounter inline_cfunc_optimized_send_count
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
          v28:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
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
          v25:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall v25, :String#length@0x1040
          CheckInterrupts
          Return v27
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
          v27:Class[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Class@0x1018)
          PatchPoint MethodRedefined(Class@0x1018, ===@0x1020, cme:0x1028)
          v31:BoolExact = IsA v10, v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v31
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
          v27:ModuleExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Module@0x1018)
          PatchPoint MethodRedefined(Module@0x1018, ===@0x1020, cme:0x1028)
          IncrCounter inline_cfunc_optimized_send_count
          v32:BoolExact = CCall v27, :Module#===@0x1050, v10
          CheckInterrupts
          Return v32
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
          v25:Class[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, is_a?@0x1011, cme:0x1018)
          v29:StringExact = GuardType v10, StringExact
          v30:BoolExact = IsA v29, v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
          v25:ModuleExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, is_a?@0x1020, cme:0x1028)
          v29:StringExact = GuardType v10, StringExact
          v30:BasicObject = CCallWithFrame v29, :Kernel#is_a?@0x1050, v25
          CheckInterrupts
          Return v30
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
          v29:Class[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, is_a?@0x1020, cme:0x1028)
          v33:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
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
          v31:Class[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Class@0x1018)
          PatchPoint MethodRedefined(Class@0x1018, ===@0x1020, cme:0x1028)
          IncrCounter inline_cfunc_optimized_send_count
          v23:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v23
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
          v25:Class[String@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, kind_of?@0x1011, cme:0x1018)
          v29:StringExact = GuardType v10, StringExact
          v30:BoolExact = IsA v29, v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
          v25:ModuleExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, kind_of?@0x1020, cme:0x1028)
          v29:StringExact = GuardType v10, StringExact
          v30:BasicObject = CCallWithFrame v29, :Kernel#kind_of?@0x1050, v25
          CheckInterrupts
          Return v30
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
          v29:Class[Integer@0x1010] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(String@0x1018)
          PatchPoint MethodRedefined(String@0x1018, kind_of?@0x1020, cme:0x1028)
          v33:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn counting_complex_feature_use_for_fallback() {
        eval("
            define_method(:fancy) { |_a, *_b, kw: 100, **kw_rest, &block| }
            def test = fancy(1)
            test
        ");
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          IncrCounter complex_arg_pass_param_block
          IncrCounter complex_arg_pass_param_kwrest
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
        assert_snapshot!(hir_string("call_forwardable"), @r"
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
          IncrCounter complex_arg_pass_param_forwardable
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
          v29:StringExact = GuardType v10, StringExact
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string_proc("TEST"), @r"
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
          v43:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v47:Class[C@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          v13:StaticSymbol[:_lex_actions] = Const Value(VALUE(0x1038))
          v15:TrueClass = Const Value(true)
          PatchPoint NoSingletonClass(Class@0x1040)
          PatchPoint MethodRedefined(Class@0x1040, respond_to?@0x1048, cme:0x1050)
          PatchPoint MethodRedefined(Class@0x1040, _lex_actions@0x1078, cme:0x1080)
          v55:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v26:StaticSymbol[:CORRECT] = Const Value(VALUE(0x10a8))
          CheckInterrupts
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
          v25:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v29:Class[C@0x1008] = Const Value(VALUE(0x1008))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoSingletonClass(Class@0x1040)
          PatchPoint MethodRedefined(Class@0x1040, name@0x1048, cme:0x1050)
          IncrCounter inline_cfunc_optimized_send_count
          v35:StringExact|NilClass = CCall v29, :Module#name@0x1078
          CheckInterrupts
          Return v35
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
          v23:HeapObject[class_exact:C] = GuardType v10, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v27:Class[C@0x1008] = Const Value(VALUE(0x1008))
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_fold_fixnum_class() {
        eval(r#"
            def test = 5.class
            test
        "#);
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
          v10:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, class@0x1008, cme:0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v22:Class[Integer@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_fold_singleton_class() {
        eval(r#"
            def test = self.class
            test
        "#);
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, class@0x1008, cme:0x1010)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Class[Object@0x1038] = Const Value(VALUE(0x1038))
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v23
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
         v11:BasicObject = LoadArg :_b@2
         v12:BasicObject = LoadArg :_c@3
         v13:NilClass = Const Value(nil)
         Jump bb3(v9, v10, v11, v12, v13)
       bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:BasicObject, v19:NilClass):
         CheckInterrupts
         SetLocal :formatted, l0, EP@3, v16
         PatchPoint SingleRactorMode
         v60:HeapBasicObject = GuardType v15, HeapBasicObject
         v61:CShape = LoadField v60, :_shape_id@0x1003
         v62:CShape[0x1004] = GuardBitEquals v61, CShape(0x1004)
         StoreField v60, :@formatted@0x1005, v16
         WriteBarrier v60, v16
         v65:CShape[0x1006] = Const CShape(0x1006)
         StoreField v60, :_shape_id@0x1003, v65
         v47:Class[VMFrozenCore] = Const Value(VALUE(0x1008))
         PatchPoint NoSingletonClass(Class@0x1010)
         PatchPoint MethodRedefined(Class@0x1010, lambda@0x1018, cme:0x1020)
         v70:BasicObject = CCallWithFrame v47, :RubyVM::FrozenCore.lambda@0x1048, block=0x1050
         v50:CPtr = GetEP 0
         v51:BasicObject = LoadField v50, :a@0x1001
         v52:BasicObject = LoadField v50, :_b@0x1002
         v53:BasicObject = LoadField v50, :_c@0x1058
         v54:BasicObject = LoadField v50, :formatted@0x1059
         CheckInterrupts
         Return v70
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozen@0x1010)
          PatchPoint MethodRedefined(TestFrozen@0x1010, a@0x1018, cme:0x1020)
          v29:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestMultiIvars@0x1010)
          PatchPoint MethodRedefined(TestMultiIvars@0x1010, b@0x1018, cme:0x1020)
          v29:Fixnum[20] = Const Value(20)
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenStr@0x1010)
          PatchPoint MethodRedefined(TestFrozenStr@0x1010, name@0x1018, cme:0x1020)
          v29:StringExact[VALUE(0x1048)] = Const Value(VALUE(0x1048))
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenNil@0x1010)
          PatchPoint MethodRedefined(TestFrozenNil@0x1010, value@0x1018, cme:0x1020)
          v29:NilClass = Const Value(nil)
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestUnfrozen@0x1010)
          PatchPoint MethodRedefined(TestUnfrozen@0x1010, a@0x1018, cme:0x1020)
          v25:CShape = LoadField v20, :_shape_id@0x1048
          v26:CShape[0x1049] = GuardBitEquals v25, CShape(0x1049)
          v27:BasicObject = LoadField v20, :@a@0x104a
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestAttrReader@0x1010)
          PatchPoint MethodRedefined(TestAttrReader@0x1010, value@0x1018, cme:0x1020)
          v29:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenSym@0x1010)
          PatchPoint MethodRedefined(TestFrozenSym@0x1010, sym@0x1018, cme:0x1020)
          v29:StaticSymbol[:hello] = Const Value(VALUE(0x1048))
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
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
          v20:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestFrozenBool@0x1010)
          PatchPoint MethodRedefined(TestFrozenBool@0x1010, flag@0x1018, cme:0x1020)
          v29:TrueClass = Const Value(true)
          CheckInterrupts
          Return v29
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
          v23:HeapObject[class_exact:TestDynamic] = GuardType v10, HeapObject[class_exact:TestDynamic]
          v26:CShape = LoadField v23, :_shape_id@0x1040
          v27:CShape[0x1041] = GuardBitEquals v26, CShape(0x1041)
          v28:BasicObject = LoadField v23, :@val@0x1042
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
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
          v27:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(TestNestedAccess@0x1010)
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, x@0x1018, cme:0x1020)
          v52:Fixnum[100] = Const Value(100)
          PatchPoint StableConstantNames(0x1048, NESTED_FROZEN)
          v33:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, y@0x1050, cme:0x1058)
          v54:Fixnum[200] = Const Value(200)
          PatchPoint MethodRedefined(Integer@0x1080, +@0x1088, cme:0x1090)
          v55:Fixnum[300] = Const Value(300)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v55
        ");
    }

    #[test]
    fn test_dont_fold_load_field_with_primitive_return_type() {
        eval(r#"
            S = "abc".freeze
            def test = S.bytesize
            test
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, S)
          v20:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, bytesize@0x1018, cme:0x1020)
          v24:CInt64 = LoadField v20, :len@0x1048
          v25:Fixnum = BoxFixnum v24
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string_proc("C.instance_method(:callprivate)"), @r"
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
          v19:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v22:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v22
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v21:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:BasicObject = Send v21, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v12
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
        assert_snapshot!(hir_string_proc("BasicObject.instance_method(:callprivate)"), @r"
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
          v21:BasicObjectExact = GuardType v6, BasicObjectExact
          v22:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v21:BasicObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:BasicObject = Send v21, :initialize # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v12
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
        assert_snapshot!(hir_string("test"), @r"
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
          v21:ObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:BasicObject = Send v21, :toplevel_method # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v12
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
        assert_snapshot!(hir_string_proc("C.instance_method(:callprotected)"), @r"
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
          v19:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v22:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v22
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
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v21:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:BasicObject = Send v21, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          CheckInterrupts
          Return v12
        ");
    }

    // Test that when a singleton class has been seen for a class, we skip the
    // NoSingletonClass optimization to avoid an invalidation loop.
    #[test]
    fn test_skip_optimization_after_singleton_class_seen() {
        // First, trigger the singleton class callback for String by creating a singleton class.
        // This should mark String as having had a singleton class seen.
        eval(r#"
            "hello".singleton_class
        "#);

        // Now define and compile a method that would normally be optimized with NoSingletonClass.
        // Since String has had a singleton class, the optimization should be skipped and we
        // should fall back to SendWithoutBlock.
        eval(r#"
            def test(s)
              s.length
            end
            test("asdf")
        "#);

        // The output should NOT have NoSingletonClass patchpoint for String, and should
        // fall back to SendWithoutBlock instead of the optimized CCall path.
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
          v16:BasicObject = Send v10, :length # SendFallbackReason: Singleton class previously created for receiver class
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_invokesuper_to_iseq_optimizes_to_direct() {
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
        assert!(hir.contains("SendDirect"), "Should optimize to SendDirect for call without args or block:\n{hir}");

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
          PatchPoint MethodRedefined(A@0x1000, foo@0x1008, cme:0x1010)
          v18:CPtr = GetEP 0
          v19:RubyValue = LoadField v18, :_ep_method_entry@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :_ep_specval@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:BasicObject = SendDirect v6, 0x1050, :foo (0x1060)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_invokesuper_from_a_block() {
        _ = eval("
            define_method(:itself) { super() }
            itself
        ");

        assert_snapshot!(hir_string("itself"), @r"
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
    fn test_invokesuper_with_positional_args_optimizes_to_direct() {
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
        assert!(hir.contains("SendDirect"), "Should optimize to SendDirect for call without args or block:\n{hir}");

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
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
          PatchPoint MethodRedefined(A@0x1008, foo@0x1010, cme:0x1018)
          v28:CPtr = GetEP 0
          v29:RubyValue = LoadField v28, :_ep_method_entry@0x1040
          v30:CallableMethodEntry[VALUE(0x1048)] = GuardBitEquals v29, Value(VALUE(0x1048))
          v31:RubyValue = LoadField v28, :_ep_specval@0x1050
          v32:FalseClass = GuardBitEquals v31, Value(false)
          v33:BasicObject = SendDirect v9, 0x1058, :foo (0x1068), v10
          v18:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1070, +@0x1078, cme:0x1080)
          v36:Fixnum = GuardType v33, Fixnum
          v37:Fixnum = FixnumAdd v36, v18
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
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
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:ArrayExact = LoadField v2, :x@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :x@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
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
        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb3(v1)
        bb2():
          EntryPoint JIT(0)
          v4:BasicObject = LoadArg :self@0
          Jump bb3(v4)
        bb3(v6:BasicObject):
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

        assert_snapshot!(hir, @r"
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
          v19:RubyValue = LoadField v18, :_ep_method_entry@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :_ep_specval@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          v24:Fixnum = CCall v6, :Hash#size@0x1050
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string_proc("C.instance_method(:initialize)"), @r"
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
          v19:RubyValue = LoadField v18, :_ep_method_entry@0x1038
          v20:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v19, Value(VALUE(0x1040))
          v21:RubyValue = LoadField v18, :_ep_specval@0x1048
          v22:FalseClass = GuardBitEquals v21, Value(false)
          v23:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
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

        assert_snapshot!(hir, @r"
        fn byteindex@<compiled>:3:
        bb1():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :needle@0x1000
          v4:BasicObject = LoadField v2, :offset@0x1001
          v5:CPtr = LoadPC
          v6:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v7:CBool = IsBitEqual v5, v6
          IfTrue v7, bb3(v1, v3, v4)
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
          PatchPoint MethodRedefined(String@0x1018, byteindex@0x1020, cme:0x1028)
          v44:CPtr = GetEP 0
          v45:RubyValue = LoadField v44, :_ep_method_entry@0x1050
          v46:CallableMethodEntry[VALUE(0x1058)] = GuardBitEquals v45, Value(VALUE(0x1058))
          v47:RubyValue = LoadField v44, :_ep_specval@0x1060
          v48:FalseClass = GuardBitEquals v47, Value(false)
          v49:BasicObject = CCallVariadic v28, :String#byteindex@0x1068, v29, v30
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
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :blk@0x1000
          v4:NilClass = Const Value(nil)
          Jump bb3(v1, v3, v4)
        bb2():
          EntryPoint JIT(0)
          v7:BasicObject = LoadArg :self@0
          v8:BasicObject = LoadArg :blk@1
          v9:NilClass = Const Value(nil)
          Jump bb3(v7, v8, v9)
        bb3(v11:BasicObject, v12:BasicObject, v13:NilClass):
          PatchPoint NoSingletonClass(B@0x1008)
          PatchPoint MethodRedefined(B@0x1008, proc@0x1010, cme:0x1018)
          v39:HeapObject[class_exact:B] = GuardType v11, HeapObject[class_exact:B]
          v40:BasicObject = CCallWithFrame v39, :Kernel#proc@0x1040, block=0x1048
          v19:CPtr = GetEP 0
          v20:BasicObject = LoadField v19, :blk@0x1050
          SetLocal :other_block, l0, EP@3, v40
          v27:CPtr = GetEP 0
          v28:BasicObject = LoadField v27, :other_block@0x1051
          v30:BasicObject = InvokeSuper v11, 0x1058, v28 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v30
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
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :items@0x1000
          Jump bb3(v1, v3)
        bb2():
          EntryPoint JIT(0)
          v6:BasicObject = LoadArg :self@0
          v7:BasicObject = LoadArg :items@1
          Jump bb3(v6, v7)
        bb3(v9:BasicObject, v10:BasicObject):
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
          v1:BasicObject = LoadSelf
          v2:CPtr = LoadSP
          v3:BasicObject = LoadField v2, :content@0x1000
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
          v21:StringExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          v22:StringExact = StringCopy v21
          Jump bb5(v17, v22)
        bb4():
          EntryPoint JIT(1)
          v14:BasicObject = LoadArg :self@0
          v15:BasicObject = LoadArg :content@1
          Jump bb5(v14, v15)
        bb5(v25:BasicObject, v26:BasicObject):
          v32:BasicObject = InvokeSuper v25, 0x1020, v26 # SendFallbackReason: super: complex argument passing to `super` call
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
          IfFalse v16, bb6(v9, v17)
          v19:Truthy = RefineType v10, Truthy
          CheckInterrupts
          v27:Truthy = RefineType v19, Truthy
          CheckInterrupts
          v35:Truthy = RefineType v27, Truthy
          v38:Fixnum[3] = Const Value(3)
          CheckInterrupts
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
          v15:CBool = HasType v10, HeapObject[class_exact:C]
          IfTrue v15, bb5(v9, v10, v10)
          v24:CBool = HasType v10, HeapObject[class_exact:D]
          IfTrue v24, bb6(v9, v10, v10)
          v33:BasicObject = Send v10, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v9, v10, v33)
        bb5(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1010, cme:0x1018)
          IncrCounter inline_iseq_optimized_send_count
          v56:Fixnum[3] = Const Value(3)
          Jump bb4(v16, v17, v56)
        bb6(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          PatchPoint NoSingletonClass(D@0x1040)
          PatchPoint MethodRedefined(D@0x1040, foo@0x1010, cme:0x1048)
          IncrCounter inline_iseq_optimized_send_count
          v58:Fixnum[4] = Const Value(4)
          Jump bb4(v25, v26, v58)
        bb4(v35:BasicObject, v36:BasicObject, v37:BasicObject):
          v40:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1070, +@0x1078, cme:0x1080)
          v61:Fixnum = GuardType v37, Fixnum
          v62:Fixnum = FixnumAdd v61, v40
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v62
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
          v15:CBool = HasType v10, HeapObject[class_exact:C]
          IfTrue v15, bb5(v9, v10, v10)
          v24:CBool = HasType v10, Fixnum
          IfTrue v24, bb6(v9, v10, v10)
          v33:BasicObject = Send v10, :itself # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb4(v9, v10, v33)
        bb5(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          v20:HeapObject[class_exact:C] = RefineType v18, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, itself@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
          Jump bb4(v16, v17, v20)
        bb6(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          v29:Fixnum = RefineType v27, Fixnum
          PatchPoint MethodRedefined(Integer@0x1040, itself@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
          Jump bb4(v25, v26, v29)
        bb4(v35:BasicObject, v36:BasicObject, v37:BasicObject):
          CheckInterrupts
          Return v37
        ");
    }

    #[test]
    fn upgrade_self_type_to_heap_after_setivar() {
        eval("
        def test
          @a = 1
          @b = 2
          @c = 3
          @d = 4
        end
        test
        ");
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
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          v42:HeapBasicObject = GuardType v6, HeapBasicObject
          v43:CShape = LoadField v42, :_shape_id@0x1000
          v44:CShape[0x1001] = GuardBitEquals v43, CShape(0x1001)
          StoreField v42, :@a@0x1002, v10
          WriteBarrier v42, v10
          v47:CShape[0x1003] = Const CShape(0x1003)
          StoreField v42, :_shape_id@0x1000, v47
          v14:HeapBasicObject = RefineType v6, HeapBasicObject
          v17:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          v50:CShape = LoadField v14, :_shape_id@0x1000
          v51:CShape[0x1003] = GuardBitEquals v50, CShape(0x1003)
          StoreField v14, :@b@0x1004, v17
          WriteBarrier v14, v17
          v54:CShape[0x1005] = Const CShape(0x1005)
          StoreField v14, :_shape_id@0x1000, v54
          v21:HeapBasicObject = RefineType v14, HeapBasicObject
          v24:Fixnum[3] = Const Value(3)
          PatchPoint SingleRactorMode
          v57:CShape = LoadField v21, :_shape_id@0x1000
          v58:CShape[0x1005] = GuardBitEquals v57, CShape(0x1005)
          StoreField v21, :@c@0x1006, v24
          WriteBarrier v21, v24
          v61:CShape[0x1007] = Const CShape(0x1007)
          StoreField v21, :_shape_id@0x1000, v61
          v28:HeapBasicObject = RefineType v21, HeapBasicObject
          v31:Fixnum[4] = Const Value(4)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_new_shape_needs_extension
          SetIvar v28, :@d, v31
          CheckInterrupts
          Return v31
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
          v8:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v9:CBool = IsBitEqual v7, v8
          IfTrue v9, bb3(v1, v3, v4, v5, v6)
          v11:CPtr[CPtr(0x1008)] = Const CPtr(0x1010)
          v12:CBool = IsBitEqual v7, v11
          IfTrue v12, bb5(v1, v3, v4, v5, v6)
          Jump bb7(v1, v3, v4, v5, v6)
        bb2():
          EntryPoint JIT(0)
          v16:BasicObject = LoadArg :self@0
          v17:BasicObject = LoadArg :list@1
          v18:NilClass = Const Value(nil)
          v19:NilClass = Const Value(nil)
          v20:NilClass = Const Value(nil)
          Jump bb3(v16, v17, v18, v19, v20)
        bb3(v36:BasicObject, v37:BasicObject, v38:BasicObject, v39:BasicObject, v40:NilClass):
          v43:NilClass = Const Value(nil)
          SetLocal :sep, l0, EP@5, v43
          Jump bb5(v36, v37, v43, v39, v40)
        bb4():
          EntryPoint JIT(1)
          v23:BasicObject = LoadArg :self@0
          v24:BasicObject = LoadArg :list@1
          v25:BasicObject = LoadArg :sep@2
          v26:NilClass = Const Value(nil)
          v27:NilClass = Const Value(nil)
          Jump bb5(v23, v24, v25, v26, v27)
        bb5(v47:BasicObject, v48:BasicObject, v49:BasicObject, v50:BasicObject, v51:NilClass):
          v54:StaticSymbol[:each] = Const Value(VALUE(0x1018))
          SetLocal :iter_method, l0, EP@4, v54
          Jump bb7(v47, v48, v49, v54, v51)
        bb6():
          EntryPoint JIT(2)
          v30:BasicObject = LoadArg :self@0
          v31:BasicObject = LoadArg :list@1
          v32:BasicObject = LoadArg :sep@2
          v33:BasicObject = LoadArg :iter_method@3
          v34:NilClass = Const Value(nil)
          Jump bb7(v30, v31, v32, v33, v34)
        bb7(v58:BasicObject, v59:BasicObject, v60:BasicObject, v61:BasicObject, v62:NilClass):
          CheckInterrupts
          v68:CBool = Test v60
          v69:Truthy = RefineType v60, Truthy
          IfTrue v68, bb8(v58, v59, v69, v61, v62)
          v71:Falsy = RefineType v60, Falsy
          PatchPoint NoSingletonClass(Object@0x1020)
          PatchPoint MethodRedefined(Object@0x1020, lambda@0x1028, cme:0x1030)
          v119:HeapObject[class_exact*:Object@VALUE(0x1020)] = GuardType v58, HeapObject[class_exact*:Object@VALUE(0x1020)]
          v120:BasicObject = CCallWithFrame v119, :Kernel#lambda@0x1058, block=0x1060
          v75:CPtr = GetEP 0
          v76:BasicObject = LoadField v75, :list@0x1001
          v78:BasicObject = LoadField v75, :iter_method@0x1068
          v79:BasicObject = LoadField v75, :kwsplat@0x1069
          SetLocal :sep, l0, EP@5, v120
          Jump bb8(v58, v76, v120, v78, v79)
        bb8(v83:BasicObject, v84:BasicObject, v85:BasicObject, v86:BasicObject, v87:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1070, CONST)
          v115:HashExact[VALUE(0x1078)] = Const Value(VALUE(0x1078))
          SetLocal :kwsplat, l0, EP@3, v115
          v96:CPtr = GetEP 0
          v97:BasicObject = LoadField v96, :list@0x1001
          v99:CPtr = GetEP 0
          v100:BasicObject = LoadField v99, :iter_method@0x1068
          v102:BasicObject = Send v97, 0x1080, :__send__, v100 # SendFallbackReason: Send: unsupported method type Optimized
          v103:CPtr = GetEP 0
          v104:BasicObject = LoadField v103, :list@0x1001
          v105:BasicObject = LoadField v103, :sep@0x1002
          v106:BasicObject = LoadField v103, :iter_method@0x1068
          v107:BasicObject = LoadField v103, :kwsplat@0x1069
          CheckInterrupts
          Return v102
        ");
    }

    #[test]
    fn test_array_each() {
        eval("[1, 2, 3].each { |x| x }");
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
          IfFalse v17, bb4(v8, v9)
          v35:Fixnum[0] = Const Value(0)
          Jump bb8(v8, v35)
        bb4(v23:BasicObject, v24:NilClass):
          v28:BasicObject = InvokeBuiltin <inline_expr>, v23
          CheckInterrupts
          Return v28
        bb8(v48:BasicObject, v49:Fixnum):
          v84:Array = RefineType v48, Array
          v85:CInt64 = ArrayLength v84
          v86:Fixnum = BoxFixnum v85
          v87:BoolExact = FixnumGe v49, v86
          IncrCounter inline_cfunc_optimized_send_count
          v54:CBool = Test v87
          IfFalse v54, bb7(v48, v49)
          CheckInterrupts
          Return v48
        bb7(v67:BasicObject, v68:Fixnum):
          v89:Array = RefineType v67, Array
          v90:CInt64 = UnboxFixnum v68
          v91:BasicObject = ArrayAref v89, v90
          IncrCounter inline_cfunc_optimized_send_count
          v74:BasicObject = InvokeBlock, v91 # SendFallbackReason: Uncategorized(invokeblock)
          v93:Fixnum[1] = Const Value(1)
          v94:Fixnum = FixnumAdd v68, v93
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(each)
          Jump bb8(v67, v94)
        ");
    }
}
