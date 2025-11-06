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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:TrueClass = Const Value(true)
          CheckInterrupts
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:FalseClass = Const Value(false)
          CheckInterrupts
          v33:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v30:Fixnum[3] = Const Value(3)
          v16:Fixnum[3] = Const Value(3)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v31:Fixnum[6] = Const Value(6)
          CheckInterrupts
          Return v31
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          v11:Fixnum[3] = Const Value(3)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
          v30:Fixnum[2] = Const Value(2)
          v16:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
          v31:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v31
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v11:Fixnum[1073741825] = Const Value(1073741825)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
          v23:Fixnum[-1073741825] = Const Value(-1073741825)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[6] = Const Value(6)
          v11:Fixnum[7] = Const Value(7)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
          v23:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v23
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[0] = Const Value(0)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
          v33:Fixnum = GuardType v9, Fixnum
          v40:Fixnum[0] = Const Value(0)
          v18:Fixnum[0] = Const Value(0)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
          v36:Fixnum = GuardType v9, Fixnum
          v41:Fixnum[0] = Const Value(0)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v42:Fixnum[0] = Const Value(0)
          CheckInterrupts
          Return v42
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
          v40:TrueClass = Const Value(true)
          CheckInterrupts
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
          v52:TrueClass = Const Value(true)
          CheckInterrupts
          v20:Fixnum[2] = Const Value(2)
          v21:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
          v54:TrueClass = Const Value(true)
          CheckInterrupts
          v32:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v11:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
          v40:TrueClass = Const Value(true)
          CheckInterrupts
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v11:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
          v52:TrueClass = Const Value(true)
          CheckInterrupts
          v20:Fixnum[2] = Const Value(2)
          v21:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
          v54:TrueClass = Const Value(true)
          CheckInterrupts
          v32:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v40:FalseClass = Const Value(false)
          CheckInterrupts
          v32:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v40:TrueClass = Const Value(true)
          CheckInterrupts
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
          v41:TrueClass = Const Value(true)
          CheckInterrupts
          v22:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
          v41:FalseClass = Const Value(false)
          CheckInterrupts
          v32:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v32
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:13:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(CustomEq@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(CustomEq@0x1000)
          v28:HeapObject[class_exact:CustomEq] = GuardType v9, HeapObject[class_exact:CustomEq]
          v29:BoolExact = CCallWithFrame !=@0x1038, v28, v9
          v19:NilClass = Const Value(nil)
          CheckInterrupts
          Return v19
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v24:Fixnum = GuardType v9, Fixnum
          v25:Fixnum = FixnumAdd v24, v13
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_strings!("rest", "kw", "kw_rest", "block", "post"), @r"
        fn rest@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:ArrayExact = GetLocal l0, SP@4, *
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:ArrayExact):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:ArrayExact):
          CheckInterrupts
          Return v9

        fn kw@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          CheckInterrupts
          Return v11

        fn kw_rest@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          CheckInterrupts
          Return v9

        fn block@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          Return v13

        fn post@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:ArrayExact = GetLocal l0, SP@5, *
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:ArrayExact, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:ArrayExact, v12:BasicObject):
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v20:BasicObject = SendWithoutBlockDirect v19, :foo (0x1038)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal l0, EP@3
          PatchPoint MethodRedefined(C@0x1000, fun_new_map@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v25:ArraySubclass[class_exact:C] = GuardType v13, ArraySubclass[class_exact:C]
          v26:BasicObject = CCallWithFrame fun_new_map@0x1038, v25, block=0x1040
          v16:BasicObject = GetLocal l0, EP@3
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = SendWithoutBlock v6, :foo
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v19:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v20:BasicObject = SendWithoutBlockDirect v19, :foo (0x1038)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, Integer@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendWithoutBlockDirect v20, :Integer (0x1038), v10
          CheckInterrupts
          Return v21
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:BasicObject = SendWithoutBlockDirect v21, :foo (0x1038), v10, v11
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v24:BasicObject = SendWithoutBlockDirect v23, :foo (0x1038)
          PatchPoint MethodRedefined(Object@0x1000, bar@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(Object@0x1000)
          v27:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v28:BasicObject = SendWithoutBlockDirect v27, :bar (0x1038)
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          PatchPoint MethodRedefined(Object@0x1008, puts@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Object@0x1008)
          v23:HeapObject[class_exact*:Object@VALUE(0x1008)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1008)]
          v24:BasicObject = CCallVariadic puts@0x1040, v23, v12
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:7:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v19:BasicObject = SendWithoutBlock v11, :+, v12
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_both_profiled() {
        eval("
            def test(a, b) = a + b
            test(1,2); test(3,4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v26:Fixnum = GuardType v11, Fixnum
          v27:Fixnum = GuardType v12, Fixnum
          v28:Fixnum = FixnumAdd v26, v27
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_left_profiled() {
        eval("
            def test(a) = a + 1
            test(1); test(3)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v24:Fixnum = GuardType v9, Fixnum
          v25:Fixnum = FixnumAdd v24, v13
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_right_profiled() {
        eval("
            def test(a) = 1 + a
            test(1); test(3)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v24:Fixnum = GuardType v9, Fixnum
          v25:Fixnum = FixnumAdd v13, v24
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_both_profiled() {
        eval("
            def test(a, b) = a < b
            test(1,2); test(3,4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
          v26:Fixnum = GuardType v11, Fixnum
          v27:Fixnum = GuardType v12, Fixnum
          v28:BoolExact = FixnumLt v26, v27
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_left_profiled() {
        eval("
            def test(a) = a < 1
            test(1); test(3)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
          v24:Fixnum = GuardType v9, Fixnum
          v25:BoolExact = FixnumLt v24, v13
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_right_profiled() {
        eval("
            def test(a) = 1 < a
            test(1); test(3)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
          v24:Fixnum = GuardType v9, Fixnum
          v25:BoolExact = FixnumLt v13, v24
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:Fixnum[2] = Const Value(2)
          v16:Fixnum[1] = Const Value(1)
          v24:RangeExact = NewRangeFixnum v16 NewRangeInclusive v13
          CheckInterrupts
          Return v24
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:Fixnum[2] = Const Value(2)
          v16:Fixnum[1] = Const Value(1)
          v24:RangeExact = NewRangeFixnum v16 NewRangeExclusive v13
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v21:Fixnum = GuardType v9, Fixnum
          v22:RangeExact = NewRangeFixnum v13 NewRangeInclusive v21
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v21:Fixnum = GuardType v9, Fixnum
          v22:RangeExact = NewRangeFixnum v13 NewRangeExclusive v21
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[10] = Const Value(10)
          v21:Fixnum = GuardType v9, Fixnum
          v22:RangeExact = NewRangeFixnum v21 NewRangeInclusive v13
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[10] = Const Value(10)
          v21:Fixnum = GuardType v9, Fixnum
          v22:RangeExact = NewRangeFixnum v21 NewRangeExclusive v13
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:ArrayExact = NewArray
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Array@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v26:ArrayExact = GuardType v9, ArrayExact
          v27:BasicObject = ArrayArefFixnum v26, v13
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Hash@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v26:HashExact = GuardType v9, HashExact
          v27:BasicObject = HashAref v26, v13
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:RangeExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v16:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v16
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          v15:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v16:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v18:StringExact = StringCopy v16
          v20:RangeExact = NewRange v15 NewRangeInclusive v18
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v17:ArrayExact = NewArray v11
          v20:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v20
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:HashExact = NewHash
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@6
          v3:BasicObject = GetLocal l0, SP@5
          v4:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject):
          EntryPoint JIT(0)
          v10:NilClass = Const Value(nil)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:NilClass):
          v19:StaticSymbol[:a] = Const Value(VALUE(0x1000))
          v20:StaticSymbol[:b] = Const Value(VALUE(0x1008))
          v22:HashExact = NewHash v19: v13, v20: v14
          PatchPoint NoEPEscape(test)
          v27:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v27
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:ArrayExact = ArrayDup v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:HashExact = HashDup v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v15:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:StringExact = StringCopy v13
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_DIV)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v31:Fixnum = FixnumDiv v29, v30
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MOD)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v31:Fixnum = FixnumMod v29, v30
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v29:Fixnum = GuardType v11, Fixnum
          v30:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
          v30:Fixnum = GuardType v11, Fixnum
          v31:Fixnum = GuardType v12, Fixnum
          v22:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = GetConstantPath 0x1000
          v14:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn kernel_itself_const() {
        eval("
            def test(x) = x.itself
            test(0) # profile
            test(1)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          v22:Fixnum = GuardType v9, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn kernel_itself_known_type() {
        eval("
            def test = [].itself
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v11
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, M)
          v29:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Module@0x1010, name@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(Module@0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          v34:StringExact|NilClass = CCall name@0x1048, v29
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
              x = [].length
              5
            end
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          IncrCounter inline_cfunc_optimized_send_count
          v31:Fixnum = CCall length@0x1038, v14
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v19:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v27:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1010, Class)
          v30:Class[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1020, Module)
          v33:Class[VALUE(0x1028)] = Const Value(VALUE(0x1028))
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1030, BasicObject)
          v36:Class[VALUE(0x1038)] = Const Value(VALUE(0x1038))
          v19:ArrayExact = NewArray v27, v30, v33, v36
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Enumerable)
          v23:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1010, Kernel)
          v26:ModuleExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          v15:ArrayExact = NewArray v23, v26
          CheckInterrupts
          Return v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, MY_MODULE)
          v19:ModuleSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn eliminate_array_size() {
        eval("
            def test
              x = [].size
              5
            end
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          IncrCounter inline_cfunc_optimized_send_count
          v31:Fixnum = CCall size@0x1038, v14
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[0] = Const Value(0)
          v13:BasicObject = SendWithoutBlock v10, :itself, v11
          CheckInterrupts
          Return v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BoolExact = IsBlockGiven
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string_proc("TEST"), @r"
        fn block in <compiled>@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BoolExact = IsBlockGiven
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v23:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_cfunc_optimized_send_count
          v14:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn const_send_direct_integer() {
        eval("
            def test(x) = 1.zero?
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, zero?@0x1008, cme:0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v24:BasicObject = InvokeBuiltin leaf _bi285, v13
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v16:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v18:ArrayExact = ArrayDup v16
          PatchPoint MethodRedefined(Array@0x1008, first@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          IncrCounter inline_iseq_optimized_send_count
          v32:BasicObject = InvokeBuiltin leaf _bi132, v18
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, M)
          v21:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Module@0x1010, class@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(Module@0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v26:HeapObject = InvokeBuiltin leaf _bi20, v21
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

        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v23:BasicObject = SendWithoutBlockDirect v22, :foo (0x1038)
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_opt() {
        eval("
            def foo(arg=1) = 1
            def test = foo 1
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_opt
          v12:BasicObject = SendWithoutBlock v6, :foo, v10
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_block() {
        eval("
            def foo(&block) = 1
            def test = foo {|| }
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = Send v6, 0x1000, :foo
          CheckInterrupts
          Return v11
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:Fixnum[1] = Const Value(1)
          SetLocal l0, EP@3, v13
          v18:BasicObject = Send v8, 0x1000, :foo
          v19:BasicObject = GetLocal l0, EP@3
          v22:BasicObject = GetLocal l0, EP@3
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          v12:BasicObject = SendWithoutBlock v6, :foo, v10
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_kw() {
        eval("
            def foo(a:) = 1
            def test = foo(a: 1)
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_caller_kwarg
          v12:BasicObject = SendWithoutBlock v6, :foo, v10
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_caller_kwarg
          v12:BasicObject = SendWithoutBlock v6, :foo, v10
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn dont_replace_get_constant_path_with_empty_ic() {
        eval("
            def test = Kernel
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = GetConstantPath 0x1000
          CheckInterrupts
          Return v11
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = GetConstantPath 0x1000
          CheckInterrupts
          Return v11
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Kernel)
          v19:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Foo::Bar::C)
          v19:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, new@0x1010, cme:0x1018)
          v43:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v47:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v43
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, C)
          v42:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(C@0x1008, new@0x1010, cme:0x1018)
          v45:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v48:BasicObject = SendWithoutBlockDirect v45, :initialize (0x1070), v13
          CheckInterrupts
          CheckInterrupts
          Return v45
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Object)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Object@0x1008, new@0x1010, cme:0x1018)
          v43:ObjectExact = ObjectAllocClass Object:VALUE(0x1008)
          PatchPoint MethodRedefined(Object@0x1008, initialize@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(Object@0x1008)
          v47:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v43
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, BasicObject)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(BasicObject@0x1008, new@0x1010, cme:0x1018)
          v43:BasicObjectExact = ObjectAllocClass BasicObject:VALUE(0x1008)
          PatchPoint MethodRedefined(BasicObject@0x1008, initialize@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(BasicObject@0x1008)
          v47:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          CheckInterrupts
          Return v43
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Hash)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Hash@0x1008, new@0x1010, cme:0x1018)
          v43:HashExact = ObjectAllocClass Hash:VALUE(0x1008)
          IncrCounter complex_arg_pass_param_opt
          IncrCounter complex_arg_pass_param_kw
          IncrCounter complex_arg_pass_param_block
          v18:BasicObject = SendWithoutBlock v43, :initialize
          CheckInterrupts
          CheckInterrupts
          Return v43
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Array)
          v42:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1008, new@0x1010, cme:0x1018)
          PatchPoint MethodRedefined(Class@0x1040, new@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Class@0x1040)
          v53:BasicObject = CCallVariadic new@0x1048, v42, v13
          CheckInterrupts
          Return v53
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Set)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Set@0x1008, new@0x1010, cme:0x1018)
          v16:HeapBasicObject = ObjectAlloc v40
          PatchPoint MethodRedefined(Set@0x1008, initialize@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(Set@0x1008)
          v46:SetExact = GuardType v16, SetExact
          v47:BasicObject = CCallVariadic initialize@0x1070, v46
          CheckInterrupts
          CheckInterrupts
          Return v16
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v40:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(String@0x1008, new@0x1010, cme:0x1018)
          PatchPoint MethodRedefined(Class@0x1040, new@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Class@0x1040)
          v51:BasicObject = CCallVariadic new@0x1048, v40
          CheckInterrupts
          Return v51
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Regexp)
          v44:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:NilClass = Const Value(nil)
          v13:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v15:StringExact = StringCopy v13
          PatchPoint MethodRedefined(Regexp@0x1008, new@0x1018, cme:0x1020)
          v47:RegexpExact = ObjectAllocClass Regexp:VALUE(0x1008)
          PatchPoint MethodRedefined(Regexp@0x1008, initialize@0x1048, cme:0x1050)
          PatchPoint NoSingletonClass(Regexp@0x1008)
          v51:BasicObject = CCallVariadic initialize@0x1078, v47, v15
          CheckInterrupts
          CheckInterrupts
          Return v47
        ");
    }

    #[test]
    fn test_opt_length() {
        eval("
            def test(a,b) = [a,b].length
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v17:ArrayExact = NewArray v11, v12
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          IncrCounter inline_cfunc_optimized_send_count
          v31:Fixnum = CCall length@0x1038, v17
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_opt_size() {
        eval("
            def test(a,b) = [a,b].size
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v17:ArrayExact = NewArray v11, v12
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          IncrCounter inline_cfunc_optimized_send_count
          v31:Fixnum = CCall size@0x1038, v17
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_getblockparamproxy() {
        eval("
            def test(&block) = tap(&block)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          GuardBlockParamProxy l0
          v15:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1000))
          v17:BasicObject = Send v8, 0x1008, :tap, v15
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          v12:BasicObject = GetIvar v6, :@foo
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_setinstancevariable() {
        eval("
            def test = @foo = 1
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          PatchPoint SingleRactorMode
          SetInstanceVariable v6, :@foo, v10
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_hash() {
        eval("
            def test = {}.dup.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:HashExact = NewHash
          PatchPoint MethodRedefined(Hash@0x1000, dup@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v24:BasicObject = CCallWithFrame dup@0x1038, v11
          v15:BasicObject = SendWithoutBlock v24, :freeze
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_no_elide_freeze_hash_with_args() {
        eval("
            def test = {}.freeze(nil)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:HashExact = NewHash
          v12:NilClass = Const Value(nil)
          v14:BasicObject = SendWithoutBlock v11, :freeze, v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_elide_freeze_with_refrozen_ary() {
        eval("
            def test = [].freeze.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_ary() {
        eval("
            def test = [].dup.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, dup@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v24:BasicObject = CCallWithFrame dup@0x1038, v11
          v15:BasicObject = SendWithoutBlock v24, :freeze
          CheckInterrupts
          Return v15
        ");
    }

    #[test]
    fn test_no_elide_freeze_ary_with_args() {
        eval("
            def test = [].freeze(nil)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          v12:NilClass = Const Value(nil)
          v14:BasicObject = SendWithoutBlock v11, :freeze, v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_elide_freeze_with_refrozen_str() {
        eval("
            def test = ''.freeze.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_str() {
        eval("
            def test = ''.dup.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(String@0x1008)
          v25:BasicObject = CCallWithFrame dup@0x1040, v12
          v16:BasicObject = SendWithoutBlock v25, :freeze
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_no_elide_freeze_str_with_args() {
        eval("
            def test = ''.freeze(nil)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          v13:NilClass = Const Value(nil)
          v15:BasicObject = SendWithoutBlock v12, :freeze, v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_elide_uminus_with_refrozen_str() {
        eval("
            def test = -''.freeze
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_no_elide_uminus_with_unfrozen_str() {
        eval("
            def test = -''.dup
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(String@0x1008)
          v25:BasicObject = CCallWithFrame dup@0x1040, v12
          v16:BasicObject = SendWithoutBlock v25, :-@
          CheckInterrupts
          Return v16
        ");
    }

    #[test]
    fn test_objtostring_anytostring_string() {
        eval(r##"
            def test = "#{('foo')}"
        "##);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v15:StringExact = StringCopy v13
          v21:StringExact = StringConcat v10, v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:Fixnum[1] = Const Value(1)
          v13:BasicObject = ObjToString v11
          v15:String = AnyToString v11, str: v13
          v17:StringExact = StringConcat v10, v15
          CheckInterrupts
          Return v17
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

        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(String@0x1008)
          v26:String = GuardType v9, String
          v19:StringExact = StringConcat v13, v26
          CheckInterrupts
          Return v19
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

        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(MyString@0x1008)
          v26:String = GuardType v9, String
          v19:StringExact = StringConcat v13, v26
          CheckInterrupts
          Return v19
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

        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v25:BasicObject = GuardTypeNot v9, String
          PatchPoint MethodRedefined(Array@0x1008, to_s@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v30:ArrayExact = GuardType v9, ArrayExact
          v31:BasicObject = CCallWithFrame to_s@0x1040, v30
          v17:String = AnyToString v9, str: v31
          v19:StringExact = StringConcat v13, v17
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:NilClass = Const Value(nil)
          CheckInterrupts
          CheckInterrupts
          Return v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:Fixnum[1] = Const Value(1)
          CheckInterrupts
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, S)
          v24:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Array@0x1010, []@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(Array@0x1010)
          v28:BasicObject = ArrayArefFixnum v24, v12
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v28:Fixnum[5] = Const Value(5)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative() {
        eval(r##"
            def test = [4,5,6].freeze[-3]
        "##);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[-3] = Const Value(-3)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v28:Fixnum[4] = Const Value(4)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[-10]
        "##);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[-10] = Const Value(-10)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v28:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[10]
        "##);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v28:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v12:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v25:BasicObject = SendWithoutBlockDirect v12, :[] (0x1040), v13
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:ArrayExact = ArrayDup v10
          PatchPoint MethodRedefined(Array@0x1008, max@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v22:BasicObject = SendWithoutBlockDirect v12, :max (0x1040)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, MY_SET)
          v19:SetExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_regexp_type() {
        eval("
            def test = /a/
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint MethodRedefined(Object@0x1000, zero@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v30:StaticSymbol[:b] = Const Value(VALUE(0x1038))
          PatchPoint SingleRactorMode
          PatchPoint MethodRedefined(Object@0x1000, one@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(Object@0x1000)
          v27:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v30
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[100] = Const Value(100)
          v12:BasicObject = SendWithoutBlock v6, :identity, v10
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = Send v6, 0x1000, :bmethod
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Foo)
          v22:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:Fixnum[100] = Const Value(100)
          PatchPoint MethodRedefined(Class@0x1010, identity@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(Class@0x1010)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v22:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v22:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v24:NilClass = GuardType v9, NilClass
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(FalseClass@0x1000, nil?@0x1008, cme:0x1010)
          v24:FalseClass = GuardType v9, FalseClass
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(TrueClass@0x1000, nil?@0x1008, cme:0x1010)
          v24:TrueClass = GuardType v9, TrueClass
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Symbol@0x1000, nil?@0x1008, cme:0x1010)
          v24:StaticSymbol = GuardType v9, StaticSymbol
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v24:Fixnum = GuardType v9, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Float@0x1000, nil?@0x1008, cme:0x1010)
          v24:Flonum = GuardType v9, Flonum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, nil?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v25:StringExact = GuardType v9, StringExact
          v26:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_to_ccall() {
        eval("
            def test(a) = !a

            test([])
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, !@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v25:ArrayExact = GuardType v9, ArrayExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall !@0x1038, v25
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_specialize_array_empty_p_to_ccall() {
        eval("
            def test(a) = a.empty?

            test([])
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, empty?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v25:ArrayExact = GuardType v9, ArrayExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall empty?@0x1038, v25
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_specialize_hash_empty_p_to_ccall() {
        eval("
            def test(a) = a.empty?

            test({})
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, empty?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v25:HashExact = GuardType v9, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall empty?@0x1038, v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, ==@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v28:HeapObject[class_exact:C] = GuardType v11, HeapObject[class_exact:C]
          v29:CBool = IsBitEqual v28, v12
          v30:BoolExact = BoxBool v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_guard_fixnum_and_fixnum() {
        eval("
            def test(x, y) = x & y

            test(1, 2)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, 28)
          v26:Fixnum = GuardType v11, Fixnum
          v27:Fixnum = GuardType v12, Fixnum
          v28:Fixnum = FixnumAnd v26, v27
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_guard_fixnum_or_fixnum() {
        eval("
            def test(x, y) = x | y

            test(1, 2)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, 29)
          v26:Fixnum = GuardType v11, Fixnum
          v27:Fixnum = GuardType v12, Fixnum
          v28:Fixnum = FixnumOr v26, v27
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:10:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v25:HeapObject[class_exact:C] = GuardShape v22, 0x1038
          v26:BasicObject = LoadField v25, :@foo@0x1039
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:13:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v25:HeapObject[class_exact:C] = GuardShape v22, 0x1038
          v26:CPtr = LoadField v25, :_as_heap@0x1039
          v27:BasicObject = LoadField v26, :@foo@0x103a
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:20:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:BasicObject = SendWithoutBlock v9, :foo
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_optimize_send_with_block() {
        eval(r#"
            def test = [1, 2, 3].map { |x| x * 2 }
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:ArrayExact = ArrayDup v10
          PatchPoint MethodRedefined(Array@0x1008, map@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v23:BasicObject = CCallWithFrame map@0x1040, v12, block=0x1048
          CheckInterrupts
          Return v23
        ");
    }

    #[test]
    fn test_do_not_optimize_send_variadic_with_block() {
        eval(r#"
            def test = [1, 2, 3].index { |x| x == 2 }
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:ArrayExact = ArrayDup v10
          v14:BasicObject = Send v12, 0x1008, :index
          CheckInterrupts
          Return v14
        ");
    }

    #[test]
    fn test_do_not_optimize_send_with_block_forwarding() {
        eval(r#"
            def test(&block) = [].map(&block)
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:ArrayExact = NewArray
          GuardBlockParamProxy l0
          v17:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1000))
          IncrCounter complex_arg_pass_caller_blockarg
          v19:BasicObject = Send v14, 0x1008, :map, v17
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_do_not_optimize_send_to_iseq_method_with_block() {
        eval(r#"
            def foo
              yield 1
            end

            def test = foo {}
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = Send v6, 0x1000, :foo
          CheckInterrupts
          Return v11
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, O)
          v21:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(C@0x1010)
          v26:HeapObject[VALUE(0x1008)] = GuardShape v21, 0x1048
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, O)
          v21:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(C@0x1010)
          v26:HeapObject[VALUE(0x1008)] = GuardShape v21, 0x1048
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v25:HeapObject[class_exact:C] = GuardShape v22, 0x1038
          v26:NilClass = Const Value(nil)
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v25:HeapObject[class_exact:C] = GuardShape v22, 0x1038
          v26:NilClass = Const Value(nil)
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v23:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          SetIvar v23, :@foo, v14
          CheckInterrupts
          Return v14
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v23:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          SetIvar v23, :@foo, v14
          CheckInterrupts
          Return v14
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v23:BasicObject = LoadField v22, :foo@0x1038
          CheckInterrupts
          Return v23
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v22:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v23:CPtr = LoadField v22, :_as_heap@0x1038
          v24:BasicObject = LoadField v23, :foo@0x1039
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_array_reverse_returns_array() {
        eval(r#"
            def test = [].reverse
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v22:ArrayExact = CCallWithFrame reverse@0x1038, v11
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:ArrayExact = NewArray
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v14:StringExact = StringCopy v12
          PatchPoint MethodRedefined(Array@0x1008, join@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v25:StringExact = CCallVariadic join@0x1040, v11, v14
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_string_to_s_returns_string() {
        eval(r#"
            def test = "".to_s
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(String@0x1008)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_inline_string_literal_to_s() {
        eval(r#"
            def test = "foo".to_s
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v10
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(String@0x1008)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v12
        ");
    }

    #[test]
    fn test_inline_profiled_string_to_s() {
        eval(r#"
            def test(o) = o.to_s
            test "foo"
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, to_s@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v23:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:ArrayExact = ArrayDup v13
          v18:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Array@0x1008)
          v31:BasicObject = ArrayArefFixnum v15, v18
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v31
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v28:ArrayExact = GuardType v11, ArrayExact
          v29:Fixnum = GuardType v12, Fixnum
          v30:BasicObject = ArrayArefFixnum v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v28:ArraySubclass[class_exact:C] = GuardType v11, ArraySubclass[class_exact:C]
          v29:Fixnum = GuardType v12, Fixnum
          v30:BasicObject = ArrayArefFixnum v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v13:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:HashExact = HashDup v13
          v18:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(Hash@0x1008)
          v31:BasicObject = HashAref v15, v18
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v28:HashExact = GuardType v11, HashExact
          v29:BasicObject = HashAref v28, v12
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_hash_aref_subclass() {
        eval("
            class C < Hash; end
            def test(hash, key)
              hash[key]
            end
            test(C.new({0 => 3}), 0)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, []@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v28:HashSubclass[class_exact:C] = GuardType v11, HashSubclass[class_exact:C]
          v29:BasicObject = HashAref v28, v12
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, H)
          v24:HashExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          v12:StaticSymbol[:a] = Const Value(VALUE(0x1010))
          PatchPoint MethodRedefined(Hash@0x1018, []@0x1020, cme:0x1028)
          PatchPoint NoSingletonClass(Hash@0x1018)
          v28:BasicObject = HashAref v24, v12
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Thread)
          v21:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint MethodRedefined(Class@0x1010, current@0x1018, cme:0x1020)
          PatchPoint NoSingletonClass(Class@0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          v26:BasicObject = CCall current@0x1048, v21
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_optimize_array_aset() {
        eval("
            def test(arr)
              arr[1] = 10
            end
            test([])
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:Fixnum[1] = Const Value(1)
          v15:Fixnum[10] = Const Value(10)
          PatchPoint MethodRedefined(Array@0x1000, []=@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v28:ArrayExact = GuardType v9, ArrayExact
          v29:BasicObject = CCallVariadic []=@0x1038, v28, v14, v15
          CheckInterrupts
          Return v15
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1000, <<@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v26:ArrayExact = GuardType v9, ArrayExact
          ArrayPush v26, v13
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1000, push@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v24:ArrayExact = GuardType v9, ArrayExact
          ArrayPush v24, v13
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v14:Fixnum[2] = Const Value(2)
          v15:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Array@0x1000, push@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v26:ArrayExact = GuardType v9, ArrayExact
          v27:BasicObject = CCallVariadic push@0x1038, v26, v13, v14, v15
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_array_length() {
        eval("
            def test(arr) = arr.length
            test([])
        ");
        assert_contains_opcode("test", YARVINSN_opt_length);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v25:ArrayExact = GuardType v9, ArrayExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall length@0x1038, v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Array@0x1000)
          v25:ArrayExact = GuardType v9, ArrayExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall size@0x1038, v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:RegexpExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(String@0x1008, =~@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(String@0x1008)
          v26:StringExact = GuardType v9, StringExact
          v27:BasicObject = CCallWithFrame =~@0x1040, v26, v13
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_optimize_string_getbyte_fixnum() {
        eval(r#"
            def test(s, i) = s.getbyte(i)
            test("foo", 0)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, getbyte@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v26:StringExact = GuardType v11, StringExact
          v27:Fixnum = GuardType v12, Fixnum
          v28:NilClass|Fixnum = StringGetbyteFixnum v26, v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, getbyte@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v29:StringExact = GuardType v11, StringExact
          v30:Fixnum = GuardType v12, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v20:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@6
          v3:BasicObject = GetLocal l0, SP@5
          v4:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, setbyte@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v29:StringExact = GuardType v13, StringExact
          v30:Fixnum = GuardType v14, Fixnum
          v31:Fixnum = GuardType v15, Fixnum
          v32:CInt64 = UnboxFixnum v30
          v33:CInt64 = LoadField v29, :len@0x1038
          v34:CInt64 = GuardLess v32, v33
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64 = GuardGreaterEq v34, v35
          v37:StringExact = GuardNotFrozen v29
          v38:Fixnum = StringSetbyteFixnum v37, v30, v31
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v31
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@6
          v3:BasicObject = GetLocal l0, SP@5
          v4:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          PatchPoint MethodRedefined(MyString@0x1000, setbyte@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(MyString@0x1000)
          v29:StringSubclass[class_exact:MyString] = GuardType v13, StringSubclass[class_exact:MyString]
          v30:Fixnum = GuardType v14, Fixnum
          v31:Fixnum = GuardType v15, Fixnum
          v32:CInt64 = UnboxFixnum v30
          v33:CInt64 = LoadField v29, :len@0x1038
          v34:CInt64 = GuardLess v32, v33
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64 = GuardGreaterEq v34, v35
          v37:StringSubclass[class_exact:MyString] = GuardNotFrozen v29
          v38:Fixnum = StringSetbyteFixnum v37, v30, v31
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v31
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@6
          v3:BasicObject = GetLocal l0, SP@5
          v4:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, setbyte@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v29:StringExact = GuardType v13, StringExact
          v30:BasicObject = CCallWithFrame setbyte@0x1038, v29, v14, v15
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, empty?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v25:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall empty?@0x1038, v25
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, empty?@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v19:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v19
        ");
    }

    #[test]
    fn test_inline_integer_succ_with_fixnum() {
        eval("
            def test(x) = x.succ
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_succ);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, succ@0x1008, cme:0x1010)
          v24:Fixnum = GuardType v9, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, succ@0x1008, cme:0x1010)
          v24:Integer = GuardType v9, Integer
          v25:BasicObject = CCallWithFrame succ@0x1038, v24
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_optimize_string_append() {
        eval(r#"
            def test(x, y) = x << y
            test("iron", "fish")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v11, StringExact
          v29:String = GuardType v12, String
          v30:StringExact = StringAppend v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
        ");
    }

    // TODO: This should be inlined just as in the interpreter
    #[test]
    fn test_optimize_string_append_non_string() {
        eval(r#"
            def test(x, y) = x << y
            test("iron", 4)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v11, StringExact
          v29:BasicObject = CCallWithFrame <<@0x1038, v28, v12
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v11, StringExact
          v29:String = GuardType v12, String
          v30:StringExact = StringAppend v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(MyString@0x1000, <<@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(MyString@0x1000)
          v28:StringSubclass[class_exact:MyString] = GuardType v11, StringSubclass[class_exact:MyString]
          v29:BasicObject = CCallWithFrame <<@0x1038, v28, v12
          CheckInterrupts
          Return v29
        ");
    }

    #[test]
    fn test_dont_inline_integer_succ_with_args() {
        eval("
            def test = 4.succ 1
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[4] = Const Value(4)
          v11:Fixnum[1] = Const Value(1)
          v13:BasicObject = SendWithoutBlock v10, :succ, v11
          CheckInterrupts
          Return v13
        ");
    }

    #[test]
    fn test_inline_integer_xor_with_fixnum() {
        eval("
            def test(x, y) = x ^ y
            test(1, 2)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v11, Fixnum
          v26:Fixnum = GuardType v12, Fixnum
          v27:Fixnum = FixnumXor v25, v26
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v28:Fixnum = GuardType v11, Fixnum
          v29:Fixnum = GuardType v12, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v20:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v20
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_bignum_or_boolean() {
        eval("
            def test(x, y) = x ^ y
            test(4 << 70, 1)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v25:Integer = GuardType v11, Integer
          v26:BasicObject = CCallWithFrame ^@0x1038, v25, v12
          CheckInterrupts
          Return v26
        ");

        eval("
            def test(x, y) = x ^ y
            test(1, 4 << 70)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v11, Fixnum
          v26:BasicObject = CCallWithFrame ^@0x1038, v25, v12
          CheckInterrupts
          Return v26
        ");

        eval("
            def test(x, y) = x ^ y
            test(true, 0)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(TrueClass@0x1000, ^@0x1008, cme:0x1010)
          v25:TrueClass = GuardType v11, TrueClass
          v26:BasicObject = CCallWithFrame ^@0x1038, v25, v12
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_dont_inline_integer_xor_with_args() {
        eval("
            def test(x, y) = x.^()
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v17:BasicObject = SendWithoutBlock v11, :^
          CheckInterrupts
          Return v17
        ");
    }

    #[test]
    fn test_specialize_hash_size() {
        eval("
            def test(hash) = hash.size
            test({foo: 3, bar: 1, baz: 4})
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v25:HashExact = GuardType v9, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall size@0x1038, v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Hash@0x1000)
          v28:HashExact = GuardType v9, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v19:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v19
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v28:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, respond_to_missing?@0x1040, cme:0x1048)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1070, cme:0x1078)
          PatchPoint NoSingletonClass(C@0x1008)
          v30:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v28:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v14:FalseClass = Const Value(false)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v29:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v29:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v14:TrueClass = Const Value(true)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v29:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v14:Fixnum[4] = Const Value(4)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v29:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v14:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v25:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          v29:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, respond_to_missing?@0x1040, cme:0x1048)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1070, cme:0x1078)
          PatchPoint NoSingletonClass(C@0x1008)
          v30:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:7:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          PatchPoint NoSingletonClass(C@0x1008)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          v25:BasicObject = CCallVariadic respond_to?@0x1040, v24, v13
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v10
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v11:Fixnum[2] = Const Value(2)
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(Object@0x1000)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          Jump bb2(v1, v2)
        bb1(v5:BasicObject):
          EntryPoint JIT(0)
          v6:NilClass = Const Value(nil)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:NilClass):
          v14:ArrayExact = NewArray
          v18:ArrayExact = ToArray v14
          IncrCounter complex_arg_pass_caller_splat
          v20:BasicObject = SendWithoutBlock v8, :foo, v18
          v23:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v25:StringExact = StringCopy v23
          PatchPoint NoEPEscape(test)
          v29:ArrayExact = ToArray v14
          IncrCounter complex_arg_pass_caller_splat
          v31:BasicObject = SendWithoutBlock v25, :display, v29
          PatchPoint NoEPEscape(test)
          v37:ArrayExact = ToArray v14
          IncrCounter complex_arg_pass_caller_splat
          v39:BasicObject = SendWithoutBlock v8, :itself, v37
          CheckInterrupts
          Return v39
        ");
    }

    #[test]
    fn test_inline_symbol_to_sym() {
        eval(r#"
            def test(o) = o.to_sym
            test :foo
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Symbol@0x1000, to_sym@0x1008, cme:0x1010)
          v21:StaticSymbol = GuardType v9, StaticSymbol
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_inline_integer_to_i() {
        eval(r#"
            def test(o) = o.to_i
            test 5
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(Integer@0x1000, to_i@0x1008, cme:0x1010)
          v21:Fixnum = GuardType v9, Fixnum
          IncrCounter inline_iseq_optimized_send_count
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_optimize_stringexact_eq_stringexact() {
        eval(r#"
            def test(l, r) = l == r
            test("a", "b")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, ==@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v11, StringExact
          v29:String = GuardType v12, String
          v30:BoolExact = CCall String#==@0x1038, v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, ==@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v28:StringSubclass[class_exact:C] = GuardType v11, StringSubclass[class_exact:C]
          v29:String = GuardType v12, String
          v30:BoolExact = CCall String#==@0x1038, v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, ==@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v11, StringExact
          v29:String = GuardType v12, String
          v30:BoolExact = CCall String#==@0x1038, v28, v29
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v30
        ");
    }

    #[test]
    fn test_optimize_stringexact_eqq_stringexact() {
        eval(r#"
            def test(l, r) = l === r
            test("a", "b")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, ===@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v26:StringExact = GuardType v11, StringExact
          v27:String = GuardType v12, String
          v28:BoolExact = CCall String#==@0x1038, v26, v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, ===@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v26:StringSubclass[class_exact:C] = GuardType v11, StringSubclass[class_exact:C]
          v27:String = GuardType v12, String
          v28:BoolExact = CCall String#==@0x1038, v26, v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@5
          v3:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, ===@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v26:StringExact = GuardType v11, StringExact
          v27:String = GuardType v12, String
          v28:BoolExact = CCall String#==@0x1038, v26, v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, size@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v25:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall size@0x1038, v25
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
       assert_snapshot!(hir_string("test"), @r"
       fn test@<compiled>:3:
       bb0():
         EntryPoint interpreter
         v1:BasicObject = LoadSelf
         v2:BasicObject = GetLocal l0, SP@4
         Jump bb2(v1, v2)
       bb1(v5:BasicObject, v6:BasicObject):
         EntryPoint JIT(0)
         Jump bb2(v5, v6)
       bb2(v8:BasicObject, v9:BasicObject):
         PatchPoint MethodRedefined(String@0x1000, size@0x1008, cme:0x1010)
         PatchPoint NoSingletonClass(String@0x1000)
         v28:StringExact = GuardType v9, StringExact
         IncrCounter inline_cfunc_optimized_send_count
         v19:Fixnum[5] = Const Value(5)
         CheckInterrupts
         Return v19
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, bytesize@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v23:StringExact = GuardType v9, StringExact
          v24:CInt64 = LoadField v23, :len@0x1038
          v25:Fixnum = BoxFixnum v24
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, bytesize@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v26:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, length@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v25:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:Fixnum = CCall length@0x1038, v25
          CheckInterrupts
          Return v27
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          IncrCounter complex_arg_pass_param_kw
          IncrCounter complex_arg_pass_param_kwrest
          IncrCounter complex_arg_pass_param_block
          v12:BasicObject = SendWithoutBlock v6, :fancy, v10
          CheckInterrupts
          Return v12
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter complex_arg_pass_param_forwardable
          v11:BasicObject = SendWithoutBlock v6, :forwardable
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(String@0x1000, length@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(String@0x1000)
          v28:StringExact = GuardType v9, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v19:Fixnum[4] = Const Value(4)
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v40:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v43:HeapObject = InvokeBuiltin leaf _bi20, v40
          v12:StaticSymbol[:_lex_actions] = Const Value(VALUE(0x1038))
          v13:TrueClass = Const Value(true)
          PatchPoint MethodRedefined(Class@0x1040, respond_to?@0x1048, cme:0x1050)
          PatchPoint NoSingletonClass(Class@0x1040)
          v47:ModuleSubclass[class_exact*:Class@VALUE(0x1040)] = GuardType v43, ModuleSubclass[class_exact*:Class@VALUE(0x1040)]
          PatchPoint MethodRedefined(Class@0x1040, _lex_actions@0x1078, cme:0x1080)
          PatchPoint NoSingletonClass(Class@0x1040)
          v51:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v22:StaticSymbol[:CORRECT] = Const Value(VALUE(0x10a8))
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_fold_self_class_name() {
        eval(r#"
            class C; end
            def test(o) = o.class.name
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          PatchPoint NoSingletonClass(C@0x1000)
          v24:HeapObject[class_exact:C] = GuardType v9, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v27:HeapObject = InvokeBuiltin leaf _bi20, v24
          PatchPoint MethodRedefined(Class@0x1038, name@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(Class@0x1038)
          v31:ModuleSubclass[class_exact*:Class@VALUE(0x1038)] = GuardType v27, ModuleSubclass[class_exact*:Class@VALUE(0x1038)]
          IncrCounter inline_cfunc_optimized_send_count
          v33:StringExact|NilClass = CCall name@0x1070, v31
          CheckInterrupts
          Return v33
        ");
    }
}
