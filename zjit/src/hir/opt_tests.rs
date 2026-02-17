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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v33:Fixnum[3] = Const Value(3)
          IncrCounter inline_cfunc_optimized_send_count
          v17:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v34:Fixnum[6] = Const Value(6)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v34
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
          v12:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v33:Fixnum[2] = Const Value(2)
          IncrCounter inline_cfunc_optimized_send_count
          v17:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v34:Fixnum[1] = Const Value(1)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v34
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
          v12:Fixnum[1073741825] = Const Value(1073741825)
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v24:Fixnum[-1073741825] = Const Value(-1073741825)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v12:Fixnum[7] = Const Value(7)
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v24:Fixnum[42] = Const Value(42)
          IncrCounter inline_cfunc_optimized_send_count
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :n, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[0] = Const Value(0)
          v15:BasicObject = GetLocal :n, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v34:Fixnum = GuardType v15, Fixnum
          v46:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          v21:Fixnum[0] = Const Value(0)
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v39:Fixnum = GuardType v15, Fixnum
          v47:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1038, cme:0x1040)
          v48:Fixnum[0] = Const Value(0)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v48
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
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <=@0x1008, cme:0x1010)
          v59:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v23:Fixnum[2] = Const Value(2)
          v25:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, <=@0x1008, cme:0x1010)
          v61:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, >=@0x1008, cme:0x1010)
          v59:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          v23:Fixnum[2] = Const Value(2)
          v25:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, >=@0x1008, cme:0x1010)
          v61:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v42:FalseClass = Const Value(false)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v42:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v43:TrueClass = Const Value(true)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[2] = Const Value(2)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v43:FalseClass = Const Value(false)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:13:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :object, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :object, l0, EP@3
          PatchPoint NoSingletonClass(CustomEq@0x1000)
          PatchPoint MethodRedefined(CustomEq@0x1000, !=@0x1008, cme:0x1010)
          v29:HeapObject[class_exact:CustomEq] = GuardType v13, HeapObject[class_exact:CustomEq]
          v30:BoolExact = CCallWithFrame v29, :BasicObject#!=@0x1038, v13
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v13, Fixnum
          v26:Fixnum = FixnumAdd v25, v15
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v2:ArrayExact = GetLocal :array, l0, SP@4, *
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:ArrayExact):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:ArrayExact):
          v13:BasicObject = GetLocal :array, l0, EP@3
          CheckInterrupts
          Return v13

        fn kw@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :k, l0, SP@5
          v3:BasicObject = GetLocal <empty>, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:BasicObject = GetLocal <empty>, l0, EP@3
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :k, l0, EP@4
          CheckInterrupts
          Return v16

        fn kw_rest@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :k, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :k, l0, EP@3
          CheckInterrupts
          Return v13

        fn block@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :b, l0, SP@4
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
          v2:ArrayExact = GetLocal :rest, l0, SP@5, *
          v3:BasicObject = GetLocal :post, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:ArrayExact, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:ArrayExact, v12:BasicObject):
          v16:BasicObject = GetLocal :post, l0, EP@3
          CheckInterrupts
          Return v16
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendDirect v20, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[1] = Const Value(1)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, baz@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v23:BasicObject = SendDirect v22, 0x1038, :foo (0x1048), v11
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, fun_new_map@0x1008, cme:0x1010)
          v24:ArraySubclass[class_exact:C] = GuardType v13, ArraySubclass[class_exact:C]
          v25:BasicObject = SendDirect v24, 0x1038, :fun_new_map (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:7:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, bar@0x1008, cme:0x1010)
          v25:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v26:BasicObject = CCallWithFrame v25, :Enumerable#bar@0x1038, block=0x1040
          PatchPoint NoEPEscape(test)
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
          v11:BasicObject = SendWithoutBlock v6, :foo # SendFallbackReason: SendWithoutBlock: unsupported method type Null
          PatchPoint NoEPEscape(test)
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendDirect v20, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, Integer@0x1008, cme:0x1010)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v23:BasicObject = SendDirect v22, 0x1038, :Integer (0x1048), v11
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v27:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v28:BasicObject = SendDirect v27, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, bar@0x1050, cme:0x1058)
          v31:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v32:BasicObject = SendDirect v31, 0x1038, :bar (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendDirect v20, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v23:BasicObject = SendDirect v22, 0x1038, :foo (0x1048), v11
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v50:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v51:BasicObject = SendDirect v50, 0x1038, :target (0x1048)
          PatchPoint NoEPEscape(test)
          v16:Fixnum[10] = Const Value(10)
          v18:Fixnum[20] = Const Value(20)
          v20:Fixnum[30] = Const Value(30)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v54:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v55:BasicObject = SendDirect v54, 0x1038, :target (0x1048), v16, v18, v20
          PatchPoint NoEPEscape(test)
          v28:Fixnum[10] = Const Value(10)
          v30:Fixnum[20] = Const Value(20)
          v32:Fixnum[30] = Const Value(30)
          v34:Fixnum[40] = Const Value(40)
          v36:Fixnum[50] = Const Value(50)
          v38:BasicObject = SendWithoutBlock v6, :target, v28, v30, v32, v34, v36 # SendFallbackReason: Argument count does not match parameter count
          PatchPoint NoEPEscape(test)
          v43:ArrayExact = NewArray v51, v55, v38
          CheckInterrupts
          Return v43
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
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          PatchPoint NoSingletonClass(Object@0x1008)
          PatchPoint MethodRedefined(Object@0x1008, puts@0x1010, cme:0x1018)
          v24:HeapObject[class_exact*:Object@VALUE(0x1008)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1008)]
          v25:BasicObject = CCallVariadic v24, :Kernel#puts@0x1040, v12
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v27:Fixnum = GuardType v16, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v28:Fixnum = GuardType v16, Fixnum
          v29:Fixnum = GuardType v18, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v13, Fixnum
          v26:Fixnum = FixnumAdd v25, v15
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v15:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v15, Fixnum
          v26:Fixnum = FixnumAdd v13, v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn integer_aref_with_fixnum_emits_fixnum_aref() {
        eval("
            def test(a, b) = a[b]
            test(3, 4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          v30:Fixnum = GuardType v16, Fixnum
          v31:Fixnum = GuardType v18, Fixnum
          v32:Fixnum = FixnumAref v30, v31
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          v28:Fixnum = FixnumAref v10, v12
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn do_not_optimize_integer_aref_with_too_many_args() {
        eval("
            def test = 1[2, 3]
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
          v12:Fixnum[2] = Const Value(2)
          v14:Fixnum[3] = Const Value(3)
          PatchPoint MethodRedefined(Integer@0x1000, []@0x1008, cme:0x1010)
          v25:BasicObject = CCallVariadic v10, :Integer#[]@0x1038, v12, v14
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn do_not_optimize_integer_aref_with_non_fixnum() {
        eval(r#"
            def test = 1["x"]
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
          v10:Fixnum[1] = Const Value(1)
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:StringExact = StringCopy v12
          PatchPoint MethodRedefined(Integer@0x1008, []@0x1010, cme:0x1018)
          v25:BasicObject = CCallVariadic v10, :Integer#[]@0x1040, v13
          PatchPoint NoEPEscape(test)
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v28:Fixnum = GuardType v16, Fixnum
          v29:Fixnum = GuardType v18, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v13, Fixnum
          v26:BoolExact = FixnumLt v25, v15
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v15:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v25:Fixnum = GuardType v15, Fixnum
          v26:BoolExact = FixnumLt v13, v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v17:Fixnum[1] = Const Value(1)
          v27:RangeExact = NewRangeFixnum v17 NewRangeInclusive v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
          v17:Fixnum[1] = Const Value(1)
          v27:RangeExact = NewRangeFixnum v17 NewRangeExclusive v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v15:BasicObject = GetLocal :a, l0, EP@3
          v24:Fixnum = GuardType v15, Fixnum
          v25:RangeExact = NewRangeFixnum v13 NewRangeInclusive v24
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          v15:BasicObject = GetLocal :a, l0, EP@3
          v24:Fixnum = GuardType v15, Fixnum
          v25:RangeExact = NewRangeFixnum v13 NewRangeExclusive v24
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          v15:Fixnum[10] = Const Value(10)
          v24:Fixnum = GuardType v13, Fixnum
          v25:RangeExact = NewRangeFixnum v24 NewRangeInclusive v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          v15:Fixnum[10] = Const Value(10)
          v24:Fixnum = GuardType v13, Fixnum
          v25:RangeExact = NewRangeFixnum v24 NewRangeExclusive v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, []@0x1008, cme:0x1010)
          v28:ArrayExact = GuardType v13, ArrayExact
          v29:CInt64[0] = UnboxFixnum v15
          v30:CInt64 = ArrayLength v28
          v31:CInt64[0] = GuardLess v29, v30
          v32:CInt64[0] = Const CInt64(0)
          v33:CInt64[0] = GuardGreaterEq v31, v32
          v34:BasicObject = ArrayAref v28, v33
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []@0x1008, cme:0x1010)
          v28:HashExact = GuardType v13, HashExact
          v29:BasicObject = HashAref v28, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:ArrayExact = NewArray v16
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :aval, l0, SP@6
          v3:BasicObject = GetLocal :bval, l0, SP@5
          v4:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject):
          EntryPoint JIT(0)
          v10:NilClass = Const Value(nil)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:NilClass):
          v19:StaticSymbol[:a] = Const Value(VALUE(0x1000))
          v21:BasicObject = GetLocal :aval, l0, EP@5
          v23:StaticSymbol[:b] = Const Value(VALUE(0x1008))
          v25:BasicObject = GetLocal :bval, l0, EP@4
          v27:HashExact = NewHash v19: v21, v23: v25
          PatchPoint NoEPEscape(test)
          v33:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v33
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, +@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, -@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, *@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, /@0x1008, cme:0x1010)
          v34:Fixnum = GuardType v16, Fixnum
          v35:Fixnum = GuardType v18, Fixnum
          v36:Fixnum = FixnumDiv v34, v35
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v27:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v27
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, %@0x1008, cme:0x1010)
          v34:Fixnum = GuardType v16, Fixnum
          v35:Fixnum = GuardType v18, Fixnum
          v36:Fixnum = FixnumMod v34, v35
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v27:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v27
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, <@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, <=@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, >@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, >=@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, ==@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          v33:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, !=@0x1008, cme:0x1010)
          v32:Fixnum = GuardType v16, Fixnum
          PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
          v34:Fixnum = GuardType v18, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v25
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
          PatchPoint NoEPEscape(test)
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :klass, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :klass, l0, EP@3
          v15:FalseClass = Const Value(false)
          v17:BasicObject = GetConstant v13, :ARGV, v15
          PatchPoint NoEPEscape(test)
          v23:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v23
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
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          v24:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
          v31:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, name@0x1018, cme:0x1020)
          IncrCounter inline_cfunc_optimized_send_count
          v36:StringExact|NilClass = CCall v31, :Module#name@0x1048
          PatchPoint NoEPEscape(test)
          v24:Fixnum[1] = Const Value(1)
          CheckInterrupts
          Return v24
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
          v20:Class[C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          v37:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1010, Class)
          v40:Class[Class@0x1018] = Const Value(VALUE(0x1018))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1020, Module)
          v43:Class[Module@0x1028] = Const Value(VALUE(0x1028))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1030, BasicObject)
          v46:Class[BasicObject@0x1038] = Const Value(VALUE(0x1038))
          PatchPoint NoEPEscape(test)
          v30:ArrayExact = NewArray v37, v40, v43, v46
          CheckInterrupts
          Return v30
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
          v27:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1010, Kernel)
          v30:ModuleExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          PatchPoint NoEPEscape(test)
          v20:ArrayExact = NewArray v27, v30
          CheckInterrupts
          Return v20
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
          v20:ModuleSubclass[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[1] = Const Value(1)
          v12:Fixnum[0] = Const Value(0)
          v14:BasicObject = SendWithoutBlock v10, :itself, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:CPtr = GetLEP
          v23:BoolExact = IsBlockGiven v22
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v21:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v22:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(block in <compiled>)
          CheckInterrupts
          Return v22
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, block_given?@0x1008, cme:0x1010)
          v25:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v26:CPtr = GetLEP
          v27:BoolExact = IsBlockGiven v26
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v17:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v17
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
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1000, zero?@0x1008, cme:0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v25:BasicObject = InvokeBuiltin leaf <inline_expr>, v13
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v16:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v17:ArrayExact = ArrayDup v16
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, first@0x1010, cme:0x1018)
          IncrCounter inline_iseq_optimized_send_count
          v33:BasicObject = InvokeBuiltin leaf <inline_expr>, v17
          PatchPoint NoEPEscape(test)
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
          v24:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, class@0x1018, cme:0x1020)
          IncrCounter inline_iseq_optimized_send_count
          v30:Class[Module@0x1010] = Const Value(VALUE(0x1010))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :c, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :c, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          PatchPoint NoEPEscape(test)
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v31:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v8, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v34:Fixnum[1] = Const Value(1)
          PatchPoint NoEPEscape(test)
          v24:BasicObject = GetLocal :a, l0, EP@3
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn reload_local_written_in_rescue_handler() {
        eval("
            def test
              a = 1
              b = 2
              tap do
                begin
                  raise
                rescue
                  b = 3
                end
              end
              a + b
            end
            test
            test
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:NilClass = Const Value(nil)
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject):
          EntryPoint JIT(0)
          v7:NilClass = Const Value(nil)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:NilClass, v12:NilClass):
          v16:Fixnum[1] = Const Value(1)
          v20:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, tap@0x1008, cme:0x1010)
          v43:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v10, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v44:BasicObject = SendDirect v43, 0x1038, :tap (0x1048)
          v26:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint NoEPEscape(test)
          v32:BasicObject = GetLocal :a, l0, EP@4
          PatchPoint MethodRedefined(Integer@0x1050, +@0x1058, cme:0x1060)
          v47:Fixnum = GuardType v32, Fixnum
          v48:Fixnum = GuardType v26, Fixnum
          v49:Fixnum = FixnumAdd v47, v48
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v49
        ");
    }

    #[test]
    fn eval_in_block_escapes_parent_ep() {
        eval("
            class EvalLocal; def f; yield; end; end
            def test
              a = 1
              EvalLocal.new.f { eval('a = 2') }
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
          SetLocal :a, l0, EP@3, v13
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, EvalLocal)
          v59:Class[EvalLocal@0x1008] = Const Value(VALUE(0x1008))
          v21:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(EvalLocal@0x1008, new@0x1009, cme:0x1010)
          v62:HeapObject[class_exact:EvalLocal] = ObjectAllocClass EvalLocal:VALUE(0x1008)
          PatchPoint NoSingletonClass(EvalLocal@0x1008)
          PatchPoint MethodRedefined(EvalLocal@0x1008, initialize@0x1038, cme:0x1040)
          v70:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          PatchPoint NoSingletonClass(EvalLocal@0x1008)
          PatchPoint MethodRedefined(EvalLocal@0x1008, f@0x1068, cme:0x1070)
          v66:BasicObject = SendDirect v62, 0x1098, :f (0x10a8)
          v52:BasicObject = GetLocal :a, l0, EP@3
          CheckInterrupts
          Return v52
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          v13:BasicObject = SendWithoutBlock v6, :foo, v11 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[10] = Const Value(10)
          IncrCounter complex_arg_pass_param_post
          v13:BasicObject = SendWithoutBlock v6, :foo, v11 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[3] = Const Value(3)
          v13:Fixnum[1] = Const Value(1)
          v15:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v28:BasicObject = SendDirect v26, 0x1038, :foo (0x1048), v13, v15, v11
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v28:BasicObject = SendDirect v26, 0x1038, :foo (0x1048), v11, v15, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[0] = Const Value(0)
          v13:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v25:BasicObject = SendDirect v24, 0x1038, :foo (0x1048), v11, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          v15:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v41:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v42:BasicObject = SendDirect v41, 0x1038, :foo (0x1048), v11, v13, v15
          PatchPoint NoEPEscape(test)
          v22:Fixnum[1] = Const Value(1)
          v24:Fixnum[2] = Const Value(2)
          v26:Fixnum[4] = Const Value(4)
          v28:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v45:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v47:BasicObject = SendDirect v45, 0x1038, :foo (0x1048), v22, v24, v28, v26
          PatchPoint NoEPEscape(test)
          v34:ArrayExact = NewArray v42, v47
          CheckInterrupts
          Return v34
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v39:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v40:Fixnum[4] = Const Value(4)
          v42:BasicObject = SendDirect v39, 0x1038, :foo (0x1048), v11, v13, v40
          PatchPoint NoEPEscape(test)
          v20:Fixnum[1] = Const Value(1)
          v22:Fixnum[2] = Const Value(2)
          v24:Fixnum[40] = Const Value(40)
          v26:Fixnum[30] = Const Value(30)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v45:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v47:BasicObject = SendDirect v45, 0x1038, :foo (0x1048), v20, v22, v26, v24
          PatchPoint NoEPEscape(test)
          v32:ArrayExact = NewArray v42, v47
          CheckInterrupts
          Return v32
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[6] = Const Value(6)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v54:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v55:BasicObject = SendDirect v54, 0x1038, :target (0x1048), v11
          PatchPoint NoEPEscape(test)
          v18:Fixnum[10] = Const Value(10)
          v20:Fixnum[20] = Const Value(20)
          v22:Fixnum[30] = Const Value(30)
          v24:Fixnum[6] = Const Value(6)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, target@0x1008, cme:0x1010)
          v58:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v59:BasicObject = SendDirect v58, 0x1038, :target (0x1048), v18, v20, v22, v24
          PatchPoint NoEPEscape(test)
          v31:Fixnum[10] = Const Value(10)
          v33:Fixnum[20] = Const Value(20)
          v35:Fixnum[30] = Const Value(30)
          v37:Fixnum[40] = Const Value(40)
          v39:Fixnum[50] = Const Value(50)
          v41:Fixnum[60] = Const Value(60)
          v43:BasicObject = SendWithoutBlock v6, :target, v31, v33, v35, v37, v39, v41 # SendFallbackReason: Too many arguments for LIR
          PatchPoint NoEPEscape(test)
          v47:ArrayExact = NewArray v55, v59, v43
          CheckInterrupts
          Return v47
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v23:BasicObject = SendDirect v22, 0x1038, :foo (0x1048), v11
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_kwrest
          v13:BasicObject = SendWithoutBlock v6, :foo, v11 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v13
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:Fixnum[1] = Const Value(1)
          v23:BasicObject = SendDirect v20, 0x1038, :foo (0x1048), v21
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:HashExact = HashDup v11
          IncrCounter complex_arg_pass_caller_kw_splat
          v14:BasicObject = SendWithoutBlock v6, :foo, v12 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter complex_arg_pass_param_kwrest
          v11:BasicObject = SendWithoutBlock v6, :foo # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v12:StringExact = StringCopy v11
          v14:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_caller_kwarg
          v16:BasicObject = SendWithoutBlock v6, :sprintf, v12, v14 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :s, l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v16:ArrayExact = NewArray
          v20:BasicObject = GetLocal :s, l0, EP@4
          v22:TrueClass = Const Value(true)
          IncrCounter complex_arg_pass_caller_kwarg
          v24:BasicObject = Send v20, 0x1000, :each_line, v22 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          v30:BasicObject = GetLocal :a, l0, EP@3
          CheckInterrupts
          Return v30
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
          PatchPoint NoEPEscape(test)
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
          PatchPoint NoEPEscape(test)
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
          v20:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          v20:Class[Foo::Bar::C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          v51:Class[C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v54:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          v58:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v54
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
          v54:Class[C@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          v18:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(C@0x1008, new@0x1009, cme:0x1010)
          v57:HeapObject[class_exact:C] = ObjectAllocClass C:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, initialize@0x1038, cme:0x1040)
          v60:BasicObject = SendDirect v57, 0x1068, :initialize (0x1078), v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v57
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
          v51:Class[Object@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Object@0x1008, new@0x1009, cme:0x1010)
          v54:ObjectExact = ObjectAllocClass Object:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Object@0x1008)
          PatchPoint MethodRedefined(Object@0x1008, initialize@0x1038, cme:0x1040)
          v58:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v54
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
          v51:Class[BasicObject@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(BasicObject@0x1008, new@0x1009, cme:0x1010)
          v54:BasicObjectExact = ObjectAllocClass BasicObject:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(BasicObject@0x1008)
          PatchPoint MethodRedefined(BasicObject@0x1008, initialize@0x1038, cme:0x1040)
          v58:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v54
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
          v51:Class[Hash@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Hash@0x1008, new@0x1009, cme:0x1010)
          v54:HashExact = ObjectAllocClass Hash:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          IncrCounter complex_arg_pass_param_block
          v24:BasicObject = SendWithoutBlock v54, :initialize # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v54
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
          v54:Class[Array@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          v18:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Array@0x1008, new@0x1009, cme:0x1010)
          PatchPoint NoSingletonClass(Class@0x1038)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v65:BasicObject = CCallVariadic v54, :Array.new@0x1040, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v65
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
          v51:Class[Set@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(Set@0x1008, new@0x1009, cme:0x1010)
          v20:HeapBasicObject = ObjectAlloc v51
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Set@0x1008)
          PatchPoint MethodRedefined(Set@0x1008, initialize@0x1038, cme:0x1040)
          v57:SetExact = GuardType v20, SetExact
          v58:BasicObject = CCallVariadic v57, :Set#initialize@0x1068
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v20
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
          v51:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          PatchPoint MethodRedefined(String@0x1008, new@0x1009, cme:0x1010)
          PatchPoint NoSingletonClass(Class@0x1038)
          PatchPoint MethodRedefined(Class@0x1038, new@0x1009, cme:0x1010)
          v62:BasicObject = CCallVariadic v51, :String.new@0x1040
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v62
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
          v55:Class[Regexp@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:NilClass = Const Value(nil)
          v18:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v19:StringExact = StringCopy v18
          PatchPoint MethodRedefined(Regexp@0x1008, new@0x1018, cme:0x1020)
          v58:RegexpExact = ObjectAllocClass Regexp:VALUE(0x1008)
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Regexp@0x1008)
          PatchPoint MethodRedefined(Regexp@0x1008, initialize@0x1048, cme:0x1050)
          v62:BasicObject = CCallVariadic v58, :Regexp#initialize@0x1078, v19
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          CheckInterrupts
          Return v58
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
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          v20:ArrayExact = NewArray v16, v18
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          v31:CInt64 = ArrayLength v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          v20:ArrayExact = NewArray v16, v18
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          v31:CInt64 = ArrayLength v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :block, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:CPtr = GetEP 0
          v15:CInt64 = LoadField v14, :_env_data_index_flags@0x1000
          v16:CInt64 = GuardNoBitsSet v15, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v17:CInt64 = LoadField v14, :_env_data_index_specval@0x1001
          v18:CInt64 = GuardAnyBitSet v17, CUInt64(1)
          v19:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          v21:BasicObject = Send v8, 0x1010, :tap, v19 # SendFallbackReason: Uncategorized(send)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
        ");
    }

    #[test]
    fn test_getblockparam() {
        eval("
            def test(&block) = block
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :block, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:CBool = IsBlockParamModified l0
          IfTrue v13, bb3(v8, v9)
          v24:BasicObject = GetBlockParam :block, l0, EP@3
          Jump bb5(v8, v24, v24)
        bb3(v14:BasicObject, v15:BasicObject):
          v22:BasicObject = GetLocal :block, l0, EP@3
          Jump bb5(v14, v22, v22)
        bb5(v26:BasicObject, v27:BasicObject, v28:BasicObject):
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string_proc("test"), @r"
        fn block in test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:CBool = IsBlockParamModified l1
          IfTrue v10, bb3(v6)
          v19:BasicObject = GetBlockParam :block, l1, EP@3
          Jump bb5(v6, v19)
        bb3(v11:BasicObject):
          v17:BasicObject = GetLocal :block, l1, EP@3
          Jump bb5(v11, v17)
        bb5(v21:BasicObject, v22:BasicObject):
          CheckInterrupts
          Return v22
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
          IncrCounter getivar_fallback_not_monomorphic
          v11:BasicObject = GetIvar v6, :@foo
          PatchPoint NoEPEscape(test)
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
          IncrCounter setivar_fallback_not_monomorphic
          SetIvar v6, :@foo, v10
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v17:HeapBasicObject = GuardType v6, HeapBasicObject
          v18:CShape = LoadField v17, :_shape_id@0x1000
          v19:CShape[0x1001] = GuardBitEquals v18, CShape(0x1001)
          v20:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v17:HeapBasicObject = GuardType v6, HeapBasicObject
          v18:CShape = LoadField v17, :_shape_id@0x1000
          v19:CShape[0x1001] = GuardBitEquals v18, CShape(0x1001)
          v20:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :p, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Proc@0x1000)
          PatchPoint MethodRedefined(Proc@0x1000, call@0x1008, cme:0x1010)
          v26:HeapObject[class_exact:Proc] = GuardType v13, HeapObject[class_exact:Proc]
          v27:BasicObject = InvokeProc v26, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :p, l0, EP@3
          v15:Fixnum[2] = Const Value(2)
          PatchPoint NoSingletonClass(Proc@0x1000)
          PatchPoint MethodRedefined(Proc@0x1000, []@0x1008, cme:0x1010)
          v27:HeapObject[class_exact:Proc] = GuardType v13, HeapObject[class_exact:Proc]
          v28:BasicObject = InvokeProc v27, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :p, l0, EP@3
          v15:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Proc@0x1000)
          PatchPoint MethodRedefined(Proc@0x1000, yield@0x1008, cme:0x1010)
          v26:HeapObject[class_exact:Proc] = GuardType v13, HeapObject[class_exact:Proc]
          v27:BasicObject = InvokeProc v26, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :p, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Proc@0x1000)
          PatchPoint MethodRedefined(Proc@0x1000, ===@0x1008, cme:0x1010)
          v26:HeapObject[class_exact:Proc] = GuardType v13, HeapObject[class_exact:Proc]
          v27:BasicObject = InvokeProc v26, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          v16:ArrayExact = NewArray
          v20:BasicObject = GetLocal :p, l0, EP@4
          v23:ArrayExact = ToArray v16
          PatchPoint NoEPEscape(test)
          IncrCounter complex_arg_pass_caller_splat
          v27:BasicObject = SendWithoutBlock v20, :call, v23 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :p, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :p, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_caller_kwarg
          v17:BasicObject = SendWithoutBlock v13, :call, v15 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter definedivar_fallback_not_t_object
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter definedivar_fallback_not_monomorphic
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter definedivar_fallback_too_complex
          v10:StringExact|NilClass = DefinedIvar v6, :@a
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v22:HeapBasicObject = GuardType v6, HeapBasicObject
          v23:CShape = LoadField v22, :_shape_id@0x1000
          v24:CShape[0x1001] = GuardBitEquals v23, CShape(0x1001)
          StoreField v22, :@foo@0x1002, v10
          WriteBarrier v22, v10
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          v22:HeapBasicObject = GuardType v6, HeapBasicObject
          v23:CShape = LoadField v22, :_shape_id@0x1000
          v24:CShape[0x1001] = GuardBitEquals v23, CShape(0x1001)
          StoreField v22, :@foo@0x1002, v10
          WriteBarrier v22, v10
          v27:CShape[0x1003] = Const CShape(0x1003)
          StoreField v22, :_shape_id@0x1000, v27
          PatchPoint NoEPEscape(test)
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
          v31:HeapBasicObject = GuardType v6, HeapBasicObject
          v32:CShape = LoadField v31, :_shape_id@0x1000
          v33:CShape[0x1001] = GuardBitEquals v32, CShape(0x1001)
          StoreField v31, :@foo@0x1002, v10
          WriteBarrier v31, v10
          v36:CShape[0x1003] = Const CShape(0x1003)
          StoreField v31, :_shape_id@0x1000, v36
          v14:HeapBasicObject = RefineType v6, HeapBasicObject
          PatchPoint NoEPEscape(test)
          v19:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          v39:CShape = LoadField v14, :_shape_id@0x1000
          v40:CShape[0x1003] = GuardBitEquals v39, CShape(0x1003)
          StoreField v14, :@bar@0x1004, v19
          WriteBarrier v14, v19
          v43:CShape[0x1005] = Const CShape(0x1005)
          StoreField v14, :_shape_id@0x1000, v43
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v19
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_not_t_object
          SetIvar v6, :@a, v10
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_not_monomorphic
          SetIvar v6, :@a, v10
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_too_complex
          SetIvar v6, :@a, v10
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_new_shape_too_complex
          SetIvar v6, :@abc, v10
          PatchPoint NoEPEscape(test)
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
          v11:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, dup@0x1008, cme:0x1010)
          v28:BasicObject = CCallWithFrame v10, :Kernel#dup@0x1038
          PatchPoint NoEPEscape(test)
          v18:BasicObject = SendWithoutBlock v28, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v18
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
          v10:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v14:NilClass = Const Value(nil)
          v16:BasicObject = SendWithoutBlock v10, :freeze, v14 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v16
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, dup@0x1008, cme:0x1010)
          v26:BasicObject = CCallWithFrame v10, :Kernel#dup@0x1038
          PatchPoint NoEPEscape(test)
          v16:BasicObject = SendWithoutBlock v26, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v16
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
          v10:ArrayExact = NewArray
          v12:NilClass = Const Value(nil)
          v14:BasicObject = SendWithoutBlock v10, :freeze, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          v27:BasicObject = CCallWithFrame v11, :String#dup@0x1040
          PatchPoint NoEPEscape(test)
          v17:BasicObject = SendWithoutBlock v27, :freeze # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v17
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
          v11:StringExact = StringCopy v10
          v13:NilClass = Const Value(nil)
          v15:BasicObject = SendWithoutBlock v11, :freeze, v13 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
          v11:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, dup@0x1010, cme:0x1018)
          v27:BasicObject = CCallWithFrame v11, :String#dup@0x1040
          PatchPoint NoEPEscape(test)
          v17:BasicObject = SendWithoutBlock v27, :-@ # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v17
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
          v14:StringExact = StringCopy v13
          PatchPoint NoEPEscape(test)
          v23:StringExact = StringConcat v10, v14
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v12:Fixnum[1] = Const Value(1)
          v15:BasicObject = ObjToString v12
          PatchPoint NoEPEscape(test)
          v19:String = AnyToString v12, str: v15
          v21:StringExact = StringConcat v10, v19
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v21
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1008)
          v32:String = GuardType v15, String
          PatchPoint NoEPEscape(test)
          v24:StringExact = StringConcat v13, v32
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint NoSingletonClass(MyString@0x1008)
          v32:String = GuardType v15, String
          PatchPoint NoEPEscape(test)
          v24:StringExact = StringConcat v13, v32
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:BasicObject = GetLocal :a, l0, EP@3
          v31:ArrayExact = GuardType v15, ArrayExact
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, to_s@0x1010, cme:0x1018)
          v36:BasicObject = CCallWithFrame v31, :Array#to_s@0x1040
          PatchPoint NoEPEscape(test)
          v22:String = AnyToString v15, str: v36
          v24:StringExact = StringConcat v13, v22
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
          v23:Fixnum[1] = RefineType v13, NotNil
          PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
          v27:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1010)
          PatchPoint MethodRedefined(Array@0x1010, []@0x1018, cme:0x1020)
          v31:CInt64[0] = UnboxFixnum v15
          v32:CInt64 = ArrayLength v27
          v33:CInt64[0] = GuardLess v31, v32
          v34:CInt64[0] = Const CInt64(0)
          v35:CInt64[0] = GuardGreaterEq v33, v34
          v36:BasicObject = ArrayAref v27, v35
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v36
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
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v26:CInt64[1] = UnboxFixnum v13
          v27:CInt64 = ArrayLength v11
          v28:CInt64[1] = GuardLess v26, v27
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64[1] = GuardGreaterEq v28, v29
          v33:Fixnum[5] = Const Value(5)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[-3] = Const Value(-3)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v26:CInt64[-3] = UnboxFixnum v13
          v27:CInt64 = ArrayLength v11
          v28:CInt64[-3] = GuardLess v26, v27
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64[-3] = GuardGreaterEq v28, v29
          v33:Fixnum[4] = Const Value(4)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[-10] = Const Value(-10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v26:CInt64[-10] = UnboxFixnum v13
          v27:CInt64 = ArrayLength v11
          v28:CInt64[-10] = GuardLess v26, v27
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64[-10] = GuardGreaterEq v28, v29
          v33:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v26:CInt64[10] = UnboxFixnum v13
          v27:CInt64 = ArrayLength v11
          v28:CInt64[10] = GuardLess v26, v27
          v29:CInt64[0] = Const CInt64(0)
          v30:CInt64[10] = GuardGreaterEq v28, v29
          v33:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v11:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v25:BasicObject = SendDirect v11, 0x1040, :[] (0x1050), v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:7:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v15:BasicObject = GetLocal :arr, l0, EP@3
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[10] = Const Value(10)
          v23:BasicObject = SendWithoutBlock v15, :[]=, v17, v19 # SendFallbackReason: Uncategorized(opt_aset)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:ArrayExact = ArrayDup v10
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, max@0x1010, cme:0x1018)
          v22:BasicObject = SendDirect v11, 0x1040, :max (0x1050)
          PatchPoint NoEPEscape(test)
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
          v20:SetExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, zero@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v34:StaticSymbol[:b] = Const Value(VALUE(0x1038))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, one@0x1040, cme:0x1048)
          v31:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
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
          v11:Fixnum[100] = Const Value(100)
          v13:BasicObject = SendWithoutBlock v6, :identity, v11 # SendFallbackReason: Bmethod: Proc object is not defined by an ISEQ
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = Send v6, 0x1000, :bmethod # SendFallbackReason: Send: unsupported method type Bmethod
          PatchPoint NoEPEscape(test)
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
          v26:Class[Foo@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:Fixnum[100] = Const Value(100)
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, identity@0x1018, cme:0x1020)
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v15
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
          v20:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v20
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
          v20:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v20
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
          v23:NilClass = GuardType v13, NilClass
          v24:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(FalseClass@0x1000, nil?@0x1008, cme:0x1010)
          v23:FalseClass = GuardType v13, FalseClass
          v24:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(TrueClass@0x1000, nil?@0x1008, cme:0x1010)
          v23:TrueClass = GuardType v13, TrueClass
          v24:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(Symbol@0x1000, nil?@0x1008, cme:0x1010)
          v23:StaticSymbol = GuardType v13, StaticSymbol
          v24:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
          v23:Fixnum = GuardType v13, Fixnum
          v24:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint MethodRedefined(Float@0x1000, nil?@0x1008, cme:0x1010)
          v23:Flonum = GuardType v13, Flonum
          v24:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
          v2:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, nil?@0x1008, cme:0x1010)
          v24:StringExact = GuardType v13, StringExact
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_truthy() {
        eval("
            def test(a) = !a

            test([])
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, !@0x1008, cme:0x1010)
          v24:ArrayExact = GuardType v13, ArrayExact
          v25:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_false() {
        eval("
            def test(a) = !a

            test(false)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint MethodRedefined(FalseClass@0x1000, !@0x1008, cme:0x1010)
          v23:FalseClass = GuardType v13, FalseClass
          v24:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_specialize_basicobject_not_nil() {
        eval("
            def test(a) = !a

            test(nil)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint MethodRedefined(NilClass@0x1000, !@0x1008, cme:0x1010)
          v23:NilClass = GuardType v13, NilClass
          v24:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v24
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          CheckInterrupts
          v16:CBool = Test v13
          v17:Falsy = RefineType v13, Falsy
          IfFalse v16, bb3(v8, v17)
          v19:Truthy = RefineType v13, Truthy
          v21:FalseClass = Const Value(false)
          CheckInterrupts
          Jump bb4(v8, v19, v21)
        bb3(v25:BasicObject, v26:Falsy):
          v29:NilClass = Const Value(nil)
          Jump bb4(v25, v26, v29)
        bb4(v31:BasicObject, v32:BasicObject, v33:Falsy):
          PatchPoint MethodRedefined(NilClass@0x1000, !@0x1008, cme:0x1010)
          v44:NilClass = GuardType v33, NilClass
          v45:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v45
        ");
    }

    #[test]
    fn test_specialize_array_empty_p() {
        eval("
            def test(a) = a.empty?

            test([])
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, empty?@0x1008, cme:0x1010)
          v24:ArrayExact = GuardType v13, ArrayExact
          v25:CInt64 = ArrayLength v24
          v26:CInt64[0] = Const CInt64(0)
          v27:CBool = IsBitEqual v25, v26
          v28:BoolExact = BoxBool v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
          v2:BasicObject = GetLocal :a, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :a, l0, EP@3
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, empty?@0x1008, cme:0x1010)
          v24:HashExact = GuardType v13, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v26:BoolExact = CCall v24, :Hash#empty?@0x1038
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :a, l0, SP@5
          v3:BasicObject = GetLocal :b, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :a, l0, EP@4
          v18:BasicObject = GetLocal :b, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, ==@0x1008, cme:0x1010)
          v29:HeapObject[class_exact:C] = GuardType v16, HeapObject[class_exact:C]
          v30:CBool = IsBitEqual v29, v18
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, &@0x1008, cme:0x1010)
          v28:Fixnum = GuardType v16, Fixnum
          v29:Fixnum = GuardType v18, Fixnum
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, |@0x1008, cme:0x1010)
          v28:Fixnum = GuardType v16, Fixnum
          v29:Fixnum = GuardType v18, Fixnum
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v27:CShape = LoadField v24, :_shape_id@0x1038
          v28:CShape[0x1039] = GuardBitEquals v27, CShape(0x1039)
          v29:BasicObject = LoadField v24, :@foo@0x103a
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v27:CShape = LoadField v24, :_shape_id@0x1038
          v28:CShape[0x1039] = GuardBitEquals v27, CShape(0x1039)
          v29:CPtr = LoadField v24, :_as_heap@0x103a
          v30:BasicObject = LoadField v29, :@foo@0x103b
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          v18:HeapBasicObject = GuardType v6, HeapBasicObject
          v19:CShape = LoadField v18, :_shape_id@0x1000
          v20:CShape[0x1001] = GuardBitEquals v19, CShape(0x1001)
          v21:CUInt16[0] = Const CUInt16(0)
          v22:BasicObject = CCall v18, :rb_ivar_get_at_no_ractor_check@0x1008, v21
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          v18:HeapBasicObject = GuardType v6, HeapBasicObject
          v19:CShape = LoadField v18, :_shape_id@0x1000
          v20:CShape[0x1001] = GuardBitEquals v19, CShape(0x1001)
          v21:CUInt16[0] = Const CUInt16(0)
          v22:BasicObject = CCall v18, :rb_ivar_get_at_no_ractor_check@0x1008, v21
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          v18:HeapBasicObject = GuardType v6, HeapBasicObject
          v19:CShape = LoadField v18, :_shape_id@0x1000
          v20:CShape[0x1001] = GuardBitEquals v19, CShape(0x1001)
          v21:CUInt16[0] = Const CUInt16(0)
          v22:BasicObject = CCall v18, :rb_ivar_get_at_no_ractor_check@0x1008, v21
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = SendWithoutBlock v6, :foo # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:20:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:CBool = HasType v13, HeapObject[class_exact:C]
          IfTrue v15, bb4(v8, v13, v13)
          v24:CBool = HasType v13, HeapObject[class_exact:C]
          IfTrue v24, bb5(v8, v13, v13)
          v33:BasicObject = SendWithoutBlock v13, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb3(v8, v13, v33)
        bb4(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          v20:HeapObject[class_exact:C] = RefineType v18, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          IncrCounter getivar_fallback_not_monomorphic
          v45:BasicObject = GetIvar v20, :@foo
          Jump bb3(v16, v17, v45)
        bb5(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          v29:HeapObject[class_exact:C] = RefineType v27, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          IncrCounter getivar_fallback_not_monomorphic
          v48:BasicObject = GetIvar v29, :@foo
          Jump bb3(v25, v26, v48)
        bb3(v35:BasicObject, v36:BasicObject, v37:BasicObject):
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:12:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          IncrCounter getivar_fallback_too_complex
          v25:BasicObject = GetIvar v24, :@foo
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v11:ArrayExact = ArrayDup v10
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, map@0x1010, cme:0x1018)
          v22:BasicObject = SendDirect v11, 0x1040, :map (0x1050)
          PatchPoint NoEPEscape(test)
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
          v13:ArrayExact = NewArray
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, A)
          v40:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1010, B)
          v43:ArrayExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Array@0x1020)
          PatchPoint MethodRedefined(Array@0x1020, zip@0x1028, cme:0x1030)
          v47:BasicObject = CCallVariadic v40, :zip@0x1058, v43
          PatchPoint NoEPEscape(test)
          v33:BasicObject = GetLocal :result, l0, EP@3
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_do_not_optimize_send_with_block_forwarding() {
        eval(r#"
            def test(&block) = [].map(&block)
            test { |x| x }; test { |x| x }
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :block, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:ArrayExact = NewArray
          v15:CPtr = GetEP 0
          v16:CInt64 = LoadField v15, :_env_data_index_flags@0x1000
          v17:CInt64 = GuardNoBitsSet v16, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v18:CInt64 = LoadField v15, :_env_data_index_specval@0x1001
          v19:CInt64 = GuardAnyBitSet v18, CUInt64(1)
          v20:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          IncrCounter complex_arg_pass_caller_blockarg
          v22:BasicObject = Send v13, 0x1010, :map, v20 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v22
        ");
    }

    #[test]
    fn test_replace_block_param_proxy_with_nil() {
        eval(r#"
            def test(&block) = [].map(&block)
            test; test
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :block, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:ArrayExact = NewArray
          v15:CPtr = GetEP 0
          v16:CInt64 = LoadField v15, :_env_data_index_flags@0x1000
          v17:CInt64 = GuardNoBitsSet v16, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v18:CInt64 = LoadField v15, :_env_data_index_specval@0x1001
          v19:CInt64[0] = GuardBitEquals v18, CInt64(0)
          v20:NilClass = Const Value(nil)
          IncrCounter complex_arg_pass_caller_blockarg
          v22:BasicObject = Send v13, 0x1008, :map, v20 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v22
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:ArrayExact = NewArray
          v12:CPtr = GetEP 1
          v13:CInt64 = LoadField v12, :_env_data_index_flags@0x1000
          v14:CInt64 = GuardNoBitsSet v13, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM=CUInt64(512)
          v15:CInt64 = LoadField v12, :_env_data_index_specval@0x1001
          v16:CInt64 = GuardAnyBitSet v15, CUInt64(1)
          v17:HeapObject[BlockParamProxy] = Const Value(VALUE(0x1008))
          IncrCounter complex_arg_pass_caller_blockarg
          v19:BasicObject = Send v10, 0x1010, :map, v17 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(block in test)
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          v21:BasicObject = SendDirect v20, 0x1038, :foo (0x1048)
          PatchPoint NoEPEscape(test)
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
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v29:CShape = LoadField v24, :_shape_id@0x1048
          v30:CShape[0x1049] = GuardBitEquals v29, CShape(0x1049)
          v31:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(C@0x1010)
          PatchPoint MethodRedefined(C@0x1010, foo@0x1018, cme:0x1020)
          v29:CShape = LoadField v24, :_shape_id@0x1048
          v30:CShape[0x1049] = GuardBitEquals v29, CShape(0x1049)
          v31:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v27:CShape = LoadField v24, :_shape_id@0x1038
          v28:CShape[0x1039] = GuardBitEquals v27, CShape(0x1039)
          v29:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v27:CShape = LoadField v24, :_shape_id@0x1038
          v28:CShape[0x1039] = GuardBitEquals v27, CShape(0x1039)
          v29:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v15:BasicObject = GetLocal :o, l0, EP@3
          v17:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v29:HeapObject[class_exact:C] = GuardType v15, HeapObject[class_exact:C]
          v32:CShape = LoadField v29, :_shape_id@0x1038
          v33:CShape[0x1039] = GuardBitEquals v32, CShape(0x1039)
          StoreField v29, :@foo@0x103a, v17
          WriteBarrier v29, v17
          v36:CShape[0x103b] = Const CShape(0x103b)
          StoreField v29, :_shape_id@0x1038, v36
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:6:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v15:BasicObject = GetLocal :o, l0, EP@3
          v17:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v29:HeapObject[class_exact:C] = GuardType v15, HeapObject[class_exact:C]
          v32:CShape = LoadField v29, :_shape_id@0x1038
          v33:CShape[0x1039] = GuardBitEquals v32, CShape(0x1039)
          StoreField v29, :@foo@0x103a, v17
          WriteBarrier v29, v17
          v36:CShape[0x103b] = Const CShape(0x103b)
          StoreField v29, :_shape_id@0x1038, v36
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v25:BasicObject = LoadField v24, :foo@0x1038
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v25:CPtr = LoadField v24, :_as_heap@0x1038
          v26:BasicObject = LoadField v25, :foo@0x1039
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          v28:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v29:CPtr = LoadField v28, :_as_heap@0x1038
          v30:BasicObject = LoadField v29, :foo@0x1039
          PatchPoint NoEPEscape(test)
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@5
          v3:BasicObject = GetLocal :v, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v18:BasicObject = GetLocal :o, l0, EP@4
          v20:BasicObject = GetLocal :v, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v33:HeapObject[class_exact:C] = GuardType v18, HeapObject[class_exact:C]
          v34:CUInt64 = LoadField v33, :_rbasic_flags@0x1038
          v35:CUInt64 = GuardNoBitsSet v34, RUBY_FL_FREEZE=CUInt64(2048)
          StoreField v33, :foo=@0x1039, v20
          WriteBarrier v33, v20
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@5
          v3:BasicObject = GetLocal :v, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v18:BasicObject = GetLocal :o, l0, EP@4
          v20:BasicObject = GetLocal :v, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo=@0x1008, cme:0x1010)
          v33:HeapObject[class_exact:C] = GuardType v18, HeapObject[class_exact:C]
          v34:CUInt64 = LoadField v33, :_rbasic_flags@0x1038
          v35:CUInt64 = GuardNoBitsSet v34, RUBY_FL_FREEZE=CUInt64(2048)
          v36:CPtr = LoadField v33, :_as_heap@0x1039
          StoreField v36, :foo=@0x103a, v20
          WriteBarrier v33, v20
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v22:ArrayExact = CCallWithFrame v10, :Array#reverse@0x1038
          PatchPoint NoEPEscape(test)
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
          v10:ArrayExact = NewArray
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, reverse@0x1008, cme:0x1010)
          v26:ArrayExact = CCallWithFrame v10, :Array#reverse@0x1038
          PatchPoint NoEPEscape(test)
          v18:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v18
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
          v10:ArrayExact = NewArray
          v12:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v13:StringExact = StringCopy v12
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, join@0x1010, cme:0x1018)
          v25:StringExact = CCallVariadic v10, :Array#join@0x1040, v13
          PatchPoint NoEPEscape(test)
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
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v11:StringExact = StringCopy v10
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, to_s@0x1010, cme:0x1018)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, to_s@0x1008, cme:0x1010)
          v25:StringExact = GuardType v13, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fixnum_to_s_returns_string() {
        eval(r#"
            def test(x) = x.to_s
            test 5
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, to_s@0x1008, cme:0x1010)
          v24:Fixnum = GuardType v13, Fixnum
          v25:StringExact = CCallVariadic v24, :Integer#to_s@0x1038
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_bignum_to_s_returns_string() {
        eval(r#"
            def test(x) = x.to_s
            test (2**65)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, to_s@0x1008, cme:0x1010)
          v24:Integer = GuardType v13, Integer
          v25:StringExact = CCallVariadic v24, :Integer#to_s@0x1038
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
        ");
    }

    #[test]
    fn test_fold_any_to_string_with_known_string_exact() {
        eval(r##"
            def test(x) = "#{x}"
            test 123
        "##);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v15:BasicObject = GetLocal :x, l0, EP@3
          v31:Fixnum = GuardType v15, Fixnum
          PatchPoint MethodRedefined(Integer@0x1008, to_s@0x1010, cme:0x1018)
          v35:StringExact = CCallVariadic v31, :Integer#to_s@0x1040
          PatchPoint NoEPEscape(test)
          v24:StringExact = StringConcat v13, v35
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
          v14:ArrayExact = ArrayDup v13
          v19:Fixnum[0] = Const Value(0)
          PatchPoint NoSingletonClass(Array@0x1008)
          PatchPoint MethodRedefined(Array@0x1008, []@0x1010, cme:0x1018)
          v32:CInt64[0] = UnboxFixnum v19
          v33:CInt64 = ArrayLength v14
          v34:CInt64[0] = GuardLess v32, v33
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64[0] = GuardGreaterEq v34, v35
          v37:BasicObject = ArrayAref v14, v36
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@5
          v3:BasicObject = GetLocal :idx, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :arr, l0, EP@4
          v18:BasicObject = GetLocal :idx, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, []@0x1008, cme:0x1010)
          v31:ArrayExact = GuardType v16, ArrayExact
          v32:Fixnum = GuardType v18, Fixnum
          v33:CInt64 = UnboxFixnum v32
          v34:CInt64 = ArrayLength v31
          v35:CInt64 = GuardLess v33, v34
          v36:CInt64[0] = Const CInt64(0)
          v37:CInt64 = GuardGreaterEq v35, v36
          v38:BasicObject = ArrayAref v31, v37
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v38
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
          v2:BasicObject = GetLocal :arr, l0, SP@5
          v3:BasicObject = GetLocal :idx, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :arr, l0, EP@4
          v18:BasicObject = GetLocal :idx, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, []@0x1008, cme:0x1010)
          v31:ArraySubclass[class_exact:C] = GuardType v16, ArraySubclass[class_exact:C]
          v32:Fixnum = GuardType v18, Fixnum
          v33:CInt64 = UnboxFixnum v32
          v34:CInt64 = ArrayLength v31
          v35:CInt64 = GuardLess v33, v34
          v36:CInt64[0] = Const CInt64(0)
          v37:CInt64 = GuardGreaterEq v35, v36
          v38:BasicObject = ArrayAref v31, v37
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v38
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
          v14:HashExact = HashDup v13
          v19:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Hash@0x1008)
          PatchPoint MethodRedefined(Hash@0x1008, []@0x1010, cme:0x1018)
          v32:BasicObject = HashAref v14, v19
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v2:BasicObject = GetLocal :hash, l0, SP@5
          v3:BasicObject = GetLocal :key, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :hash, l0, EP@4
          v18:BasicObject = GetLocal :key, l0, EP@3
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []@0x1008, cme:0x1010)
          v31:HashExact = GuardType v16, HashExact
          v32:BasicObject = HashAref v31, v18
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :hash, l0, SP@5
          v3:BasicObject = GetLocal :key, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :hash, l0, EP@4
          v18:BasicObject = GetLocal :key, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, []@0x1008, cme:0x1010)
          v31:HashSubclass[class_exact:C] = GuardType v16, HashSubclass[class_exact:C]
          v32:BasicObject = CCallWithFrame v31, :Hash#[]@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v27:HashExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:StaticSymbol[:a] = Const Value(VALUE(0x1010))
          PatchPoint NoSingletonClass(Hash@0x1018)
          PatchPoint MethodRedefined(Hash@0x1018, []@0x1020, cme:0x1028)
          v31:BasicObject = HashAref v27, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v13:HashExact = NewHash
          PatchPoint NoEPEscape(test)
          v22:Fixnum[1] = Const Value(1)
          v24:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []=@0x1008, cme:0x1010)
          HashAset v13, v22, v24
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :hash, l0, SP@6
          v3:BasicObject = GetLocal :key, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v21:BasicObject = GetLocal :hash, l0, EP@5
          v23:BasicObject = GetLocal :key, l0, EP@4
          v25:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, []=@0x1008, cme:0x1010)
          v40:HashExact = GuardType v21, HashExact
          HashAset v40, v23, v25
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :hash, l0, SP@6
          v3:BasicObject = GetLocal :key, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v21:BasicObject = GetLocal :hash, l0, EP@5
          v23:BasicObject = GetLocal :key, l0, EP@4
          v25:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, []=@0x1008, cme:0x1010)
          v40:HashSubclass[class_exact:C] = GuardType v21, HashSubclass[class_exact:C]
          v41:BasicObject = CCallWithFrame v40, :Hash#[]=@0x1038, v23, v25
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v24:Class[Thread@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, current@0x1018, cme:0x1020)
          v28:CPtr = LoadEC
          v29:CPtr = LoadField v28, :thread_ptr@0x1048
          v30:BasicObject = LoadField v29, :self@0x1049
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v15:BasicObject = GetLocal :arr, l0, EP@3
          v17:Fixnum[1] = Const Value(1)
          v19:Fixnum[10] = Const Value(10)
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, []=@0x1008, cme:0x1010)
          v34:ArrayExact = GuardType v15, ArrayExact
          v35:CUInt64 = LoadField v34, :_rbasic_flags@0x1038
          v36:CUInt64 = GuardNoBitsSet v35, RUBY_FL_FREEZE=CUInt64(2048)
          v37:CUInt64 = LoadField v34, :_rbasic_flags@0x1038
          v38:CUInt64 = GuardNoBitsSet v37, RUBY_ELTS_SHARED=CUInt64(4096)
          v39:CInt64[1] = UnboxFixnum v17
          v40:CInt64 = ArrayLength v34
          v41:CInt64[1] = GuardLess v39, v40
          v42:CInt64[0] = Const CInt64(0)
          v43:CInt64[1] = GuardGreaterEq v41, v42
          ArrayAset v34, v43, v19
          WriteBarrier v34, v19
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@6
          v3:BasicObject = GetLocal :index, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v21:BasicObject = GetLocal :arr, l0, EP@5
          v23:BasicObject = GetLocal :index, l0, EP@4
          v25:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, []=@0x1008, cme:0x1010)
          v40:ArrayExact = GuardType v21, ArrayExact
          v41:Fixnum = GuardType v23, Fixnum
          v42:CUInt64 = LoadField v40, :_rbasic_flags@0x1038
          v43:CUInt64 = GuardNoBitsSet v42, RUBY_FL_FREEZE=CUInt64(2048)
          v44:CUInt64 = LoadField v40, :_rbasic_flags@0x1038
          v45:CUInt64 = GuardNoBitsSet v44, RUBY_ELTS_SHARED=CUInt64(4096)
          v46:CInt64 = UnboxFixnum v41
          v47:CInt64 = ArrayLength v40
          v48:CInt64 = GuardLess v46, v47
          v49:CInt64[0] = Const CInt64(0)
          v50:CInt64 = GuardGreaterEq v48, v49
          ArrayAset v40, v50, v25
          WriteBarrier v40, v25
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :arr, l0, SP@6
          v3:BasicObject = GetLocal :index, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v21:BasicObject = GetLocal :arr, l0, EP@5
          v23:BasicObject = GetLocal :index, l0, EP@4
          v25:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(MyArray@0x1000)
          PatchPoint MethodRedefined(MyArray@0x1000, []=@0x1008, cme:0x1010)
          v40:ArraySubclass[class_exact:MyArray] = GuardType v21, ArraySubclass[class_exact:MyArray]
          v41:BasicObject = CCallVariadic v40, :Array#[]=@0x1038, v23, v25
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, <<@0x1008, cme:0x1010)
          v28:ArrayExact = GuardType v13, ArrayExact
          ArrayPush v28, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, push@0x1008, cme:0x1010)
          v27:ArrayExact = GuardType v13, ArrayExact
          ArrayPush v27, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          v15:Fixnum[1] = Const Value(1)
          v17:Fixnum[2] = Const Value(2)
          v19:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, push@0x1008, cme:0x1010)
          v31:ArrayExact = GuardType v13, ArrayExact
          v32:BasicObject = CCallVariadic v31, :Array#push@0x1038, v15, v17, v19
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
          v24:ArrayExact = GuardType v13, ArrayExact
          v25:CInt64 = ArrayLength v24
          v26:Fixnum = BoxFixnum v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :arr, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :arr, l0, EP@3
          PatchPoint NoSingletonClass(Array@0x1000)
          PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
          v24:ArrayExact = GuardType v13, ArrayExact
          v25:CInt64 = ArrayLength v24
          v26:Fixnum = BoxFixnum v25
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          v15:RegexpExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, =~@0x1010, cme:0x1018)
          v28:StringExact = GuardType v13, StringExact
          v29:BasicObject = CCallWithFrame v28, :String#=~@0x1040, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
          v2:BasicObject = GetLocal :s, l0, SP@5
          v3:BasicObject = GetLocal :i, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :s, l0, EP@4
          v18:BasicObject = GetLocal :i, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, getbyte@0x1008, cme:0x1010)
          v30:StringExact = GuardType v16, StringExact
          v31:Fixnum = GuardType v18, Fixnum
          v32:CInt64 = UnboxFixnum v31
          v33:CInt64 = LoadField v30, :len@0x1038
          v34:CInt64 = GuardLess v32, v33
          v35:CInt64[0] = Const CInt64(0)
          v36:CInt64 = GuardGreaterEq v34, v35
          v37:Fixnum = StringGetbyte v30, v34
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v37
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
          v2:BasicObject = GetLocal :s, l0, SP@5
          v3:BasicObject = GetLocal :i, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :s, l0, EP@4
          v18:BasicObject = GetLocal :i, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, getbyte@0x1008, cme:0x1010)
          v34:StringExact = GuardType v16, StringExact
          v35:Fixnum = GuardType v18, Fixnum
          v36:CInt64 = UnboxFixnum v35
          v37:CInt64 = LoadField v34, :len@0x1038
          v38:CInt64 = GuardLess v36, v37
          v39:CInt64[0] = Const CInt64(0)
          v40:CInt64 = GuardGreaterEq v38, v39
          v41:Fixnum = StringGetbyte v34, v38
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v26:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :s, l0, SP@6
          v3:BasicObject = GetLocal :idx, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v19:BasicObject = GetLocal :s, l0, EP@5
          v21:BasicObject = GetLocal :idx, l0, EP@4
          v23:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, setbyte@0x1008, cme:0x1010)
          v35:StringExact = GuardType v19, StringExact
          v36:Fixnum = GuardType v21, Fixnum
          v37:Fixnum = GuardType v23, Fixnum
          v38:CInt64 = UnboxFixnum v36
          v39:CInt64 = LoadField v35, :len@0x1038
          v40:CInt64 = GuardLess v38, v39
          v41:CInt64[0] = Const CInt64(0)
          v42:CInt64 = GuardGreaterEq v40, v41
          v43:CUInt64 = LoadField v35, :_rbasic_flags@0x1039
          v44:CUInt64 = GuardNoBitsSet v43, RUBY_FL_FREEZE=CUInt64(2048)
          v45:Fixnum = StringSetbyteFixnum v35, v36, v37
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v37
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
          v2:BasicObject = GetLocal :s, l0, SP@6
          v3:BasicObject = GetLocal :idx, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v19:BasicObject = GetLocal :s, l0, EP@5
          v21:BasicObject = GetLocal :idx, l0, EP@4
          v23:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(MyString@0x1000)
          PatchPoint MethodRedefined(MyString@0x1000, setbyte@0x1008, cme:0x1010)
          v35:StringSubclass[class_exact:MyString] = GuardType v19, StringSubclass[class_exact:MyString]
          v36:Fixnum = GuardType v21, Fixnum
          v37:Fixnum = GuardType v23, Fixnum
          v38:CInt64 = UnboxFixnum v36
          v39:CInt64 = LoadField v35, :len@0x1038
          v40:CInt64 = GuardLess v38, v39
          v41:CInt64[0] = Const CInt64(0)
          v42:CInt64 = GuardGreaterEq v40, v41
          v43:CUInt64 = LoadField v35, :_rbasic_flags@0x1039
          v44:CUInt64 = GuardNoBitsSet v43, RUBY_FL_FREEZE=CUInt64(2048)
          v45:Fixnum = StringSetbyteFixnum v35, v36, v37
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v37
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
          v2:BasicObject = GetLocal :s, l0, SP@6
          v3:BasicObject = GetLocal :idx, l0, SP@5
          v4:BasicObject = GetLocal :val, l0, SP@4
          Jump bb2(v1, v2, v3, v4)
        bb1(v7:BasicObject, v8:BasicObject, v9:BasicObject, v10:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v7, v8, v9, v10)
        bb2(v12:BasicObject, v13:BasicObject, v14:BasicObject, v15:BasicObject):
          v19:BasicObject = GetLocal :s, l0, EP@5
          v21:BasicObject = GetLocal :idx, l0, EP@4
          v23:BasicObject = GetLocal :val, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, setbyte@0x1008, cme:0x1010)
          v35:StringExact = GuardType v19, StringExact
          v36:BasicObject = CCallWithFrame v35, :String#setbyte@0x1038, v21, v23
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v36
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, empty?@0x1008, cme:0x1010)
          v24:StringExact = GuardType v13, StringExact
          v25:CInt64 = LoadField v24, :len@0x1038
          v26:CInt64[0] = Const CInt64(0)
          v27:CBool = IsBitEqual v25, v26
          v28:BoolExact = BoxBool v27
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v28
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, empty?@0x1008, cme:0x1010)
          v28:StringExact = GuardType v13, StringExact
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, succ@0x1008, cme:0x1010)
          v23:Fixnum = GuardType v13, Fixnum
          v24:Fixnum[1] = Const Value(1)
          v25:Fixnum = FixnumAdd v23, v24
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v25
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
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, succ@0x1008, cme:0x1010)
          v23:Integer = GuardType v13, Integer
          v24:BasicObject = CCallWithFrame v23, :Integer#succ@0x1038
          CheckInterrupts
          Return v24
        ");
    }

    #[test]
    fn test_inline_integer_ltlt_with_known_fixnum() {
        eval("
            def test(x) = x << 5
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, <<@0x1008, cme:0x1010)
          v27:Fixnum = GuardType v13, Fixnum
          v28:Fixnum = FixnumLShift v27, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_negative() {
        eval("
            def test(x) = x << -5
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[-5] = Const Value(-5)
          PatchPoint MethodRedefined(Integer@0x1000, <<@0x1008, cme:0x1010)
          v27:Fixnum = GuardType v13, Fixnum
          v28:BasicObject = CCallWithFrame v27, :Integer#<<@0x1038, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_out_of_range() {
        eval("
            def test(x) = x << 64
            test(4)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[64] = Const Value(64)
          PatchPoint MethodRedefined(Integer@0x1000, <<@0x1008, cme:0x1010)
          v27:Fixnum = GuardType v13, Fixnum
          v28:BasicObject = CCallWithFrame v27, :Integer#<<@0x1038, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
        ");
    }

    #[test]
    fn test_dont_inline_integer_ltlt_with_unknown_fixnum() {
        eval("
            def test(x, y) = x << y
            test(4, 5)
        ");
        assert_contains_opcode("test", YARVINSN_opt_ltlt);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, <<@0x1008, cme:0x1010)
          v30:Fixnum = GuardType v16, Fixnum
          v31:BasicObject = CCallWithFrame v30, :Integer#<<@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_inline_integer_gtgt_with_known_fixnum() {
        eval("
            def test(x) = x >> 5
            test(4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, >>@0x1008, cme:0x1010)
          v26:Fixnum = GuardType v13, Fixnum
          v27:Fixnum = FixnumRShift v26, v15
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_negative() {
        eval("
            def test(x) = x >> -5
            test(4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[-5] = Const Value(-5)
          PatchPoint MethodRedefined(Integer@0x1000, >>@0x1008, cme:0x1010)
          v26:Fixnum = GuardType v13, Fixnum
          v27:BasicObject = CCallWithFrame v26, :Integer#>>@0x1038, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_out_of_range() {
        eval("
            def test(x) = x >> 64
            test(4)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          v15:Fixnum[64] = Const Value(64)
          PatchPoint MethodRedefined(Integer@0x1000, >>@0x1008, cme:0x1010)
          v26:Fixnum = GuardType v13, Fixnum
          v27:BasicObject = CCallWithFrame v26, :Integer#>>@0x1038, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
        ");
    }

    #[test]
    fn test_dont_inline_integer_gtgt_with_unknown_fixnum() {
        eval("
            def test(x, y) = x >> y
            test(4, 5)
        ");
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, >>@0x1008, cme:0x1010)
          v29:Fixnum = GuardType v16, Fixnum
          v30:BasicObject = CCallWithFrame v29, :Integer#>>@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          v31:StringExact = GuardType v16, StringExact
          v32:String = GuardType v18, String
          v33:StringExact = StringAppend v31, v32
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
        ");
    }

    #[test]
    fn test_optimize_string_append_codepoint() {
        eval(r#"
            def test(x, y) = x << y
            test("iron", 4)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          v31:StringExact = GuardType v16, StringExact
          v32:Fixnum = GuardType v18, Fixnum
          v33:StringExact = StringAppendCodepoint v31, v32
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, <<@0x1008, cme:0x1010)
          v31:StringExact = GuardType v16, StringExact
          v32:String = GuardType v18, String
          v33:StringExact = StringAppend v31, v32
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint NoSingletonClass(MyString@0x1000)
          PatchPoint MethodRedefined(MyString@0x1000, <<@0x1008, cme:0x1010)
          v31:StringSubclass[class_exact:MyString] = GuardType v16, StringSubclass[class_exact:MyString]
          v32:BasicObject = CCallWithFrame v31, :String#<<@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
        ");
    }

    #[test]
    fn test_dont_optimize_string_append_non_string() {
        eval(r#"
            def test = "iron" << :a
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
          v11:StringExact = StringCopy v10
          v13:StaticSymbol[:a] = Const Value(VALUE(0x1008))
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, <<@0x1018, cme:0x1020)
          v26:BasicObject = CCallWithFrame v11, :String#<<@0x1048, v13
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v26
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v12:Fixnum[3] = Const Value(3)
          v14:Fixnum[3] = Const Value(3)
          v16:Fixnum[3] = Const Value(3)
          v18:BasicObject = SendWithoutBlock v10, :foo, v12, v14, v16 # SendFallbackReason: Argument count does not match parameter count
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, ascii_only?@0x1008, cme:0x1010)
          v25:StringExact = GuardType v13, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v27:BoolExact = CCall v25, :String#ascii_only?@0x1038
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[0] = Const Value(0)
          v12:BasicObject = SendWithoutBlock v10, :foo # SendFallbackReason: Argument count does not match parameter count
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[4] = Const Value(4)
          v12:Fixnum[1] = Const Value(1)
          v14:BasicObject = SendWithoutBlock v10, :succ, v12 # SendFallbackReason: SendWithoutBlock: unsupported method type Cfunc
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v29:Fixnum = GuardType v16, Fixnum
          v30:Fixnum = GuardType v18, Fixnum
          v31:Fixnum = FixnumXor v29, v30
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v33:Fixnum = GuardType v16, Fixnum
          v34:Fixnum = GuardType v18, Fixnum
          v35:Fixnum = FixnumXor v33, v34
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v26:Fixnum[42] = Const Value(42)
          CheckInterrupts
          Return v26
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v29:Integer = GuardType v16, Integer
          v30:BasicObject = CCallWithFrame v29, :Integer#^@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, ^@0x1008, cme:0x1010)
          v29:Fixnum = GuardType v16, Fixnum
          v30:BasicObject = CCallWithFrame v29, :Integer#^@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = GetLocal :y, l0, EP@3
          PatchPoint MethodRedefined(TrueClass@0x1000, ^@0x1008, cme:0x1010)
          v29:TrueClass = GuardType v16, TrueClass
          v30:BasicObject = CCallWithFrame v29, :TrueClass#^@0x1038, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :x, l0, SP@5
          v3:BasicObject = GetLocal :y, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :x, l0, EP@4
          v18:BasicObject = SendWithoutBlock v16, :^ # SendFallbackReason: Uncategorized(opt_send_without_block)
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :hash, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :hash, l0, EP@3
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          v24:HashExact = GuardType v13, HashExact
          IncrCounter inline_cfunc_optimized_send_count
          v26:Fixnum = CCall v24, :Hash#size@0x1038
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :hash, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :hash, l0, EP@3
          PatchPoint NoSingletonClass(Hash@0x1000)
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          v28:HashExact = GuardType v13, HashExact
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v27:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v31:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v27:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, respond_to_missing?@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1070, cme:0x1078)
          v33:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v27:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v31:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v17:FalseClass = Const Value(false)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v29:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v33:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v17:NilClass = Const Value(nil)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v29:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v33:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v17:TrueClass = Const Value(true)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v29:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v33:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v17:Fixnum[4] = Const Value(4)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v29:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v33:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          v17:NilClass = Const Value(nil)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v29:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1040, cme:0x1048)
          v33:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v27:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          PatchPoint MethodRedefined(C@0x1008, respond_to_missing?@0x1040, cme:0x1048)
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, foo@0x1070, cme:0x1078)
          v33:FalseClass = Const Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
          PatchPoint NoSingletonClass(C@0x1008)
          PatchPoint MethodRedefined(C@0x1008, respond_to?@0x1010, cme:0x1018)
          v27:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          v28:BasicObject = CCallVariadic v27, :Kernel#respond_to?@0x1040, v15
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v20
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:StringExact[VALUE(0x1038)] = Const Value(VALUE(0x1038))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:TrueClass = Const Value(true)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:FalseClass = Const Value(false)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[0] = Const Value(0)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[1] = Const Value(1)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v11:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v22:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:Fixnum[1] = Const Value(1)
          v13:Fixnum[2] = Const Value(2)
          v15:Fixnum[3] = Const Value(3)
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v26:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
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
          v13:ArrayExact = NewArray
          v19:ArrayExact = ToArray v13
          PatchPoint NoEPEscape(test)
          IncrCounter complex_arg_pass_caller_splat
          v23:BasicObject = SendWithoutBlock v8, :foo, v19 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          v29:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
          v30:StringExact = StringCopy v29
          v33:ArrayExact = ToArray v13
          PatchPoint NoEPEscape(test)
          IncrCounter complex_arg_pass_caller_splat
          v37:BasicObject = SendWithoutBlock v30, :display, v33 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          v45:ArrayExact = ToArray v13
          PatchPoint NoEPEscape(test)
          IncrCounter complex_arg_pass_caller_splat
          v49:BasicObject = SendWithoutBlock v8, :itself, v45 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v49
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint MethodRedefined(Symbol@0x1000, to_sym@0x1008, cme:0x1010)
          v23:StaticSymbol = GuardType v13, StaticSymbol
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint MethodRedefined(Integer@0x1000, to_i@0x1008, cme:0x1010)
          v23:Fixnum = GuardType v13, Fixnum
          IncrCounter inline_iseq_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          PatchPoint NoEPEscape(test)
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          PatchPoint NoEPEscape(test)
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
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, callee@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[123] = Const Value(123)
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:StaticSymbol[:the_block] = Const Value(VALUE(0x1000))
          v13:BasicObject = Send v6, 0x1008, :callee, v11 # SendFallbackReason: Uncategorized(send)
          PatchPoint NoEPEscape(test)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, ==@0x1008, cme:0x1010)
          v29:StringExact = GuardType v16, StringExact
          v30:String = GuardType v18, String
          v31:BoolExact = CCall v29, :String#==@0x1038, v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, ==@0x1008, cme:0x1010)
          v29:StringSubclass[class_exact:C] = GuardType v16, StringSubclass[class_exact:C]
          v30:String = GuardType v18, String
          v31:BoolExact = CCall v29, :String#==@0x1038, v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:4:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, ==@0x1008, cme:0x1010)
          v29:StringExact = GuardType v16, StringExact
          v30:String = GuardType v18, String
          v31:BoolExact = CCall v29, :String#==@0x1038, v30
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, ===@0x1008, cme:0x1010)
          v30:StringExact = GuardType v16, StringExact
          v31:String = GuardType v18, String
          v32:BoolExact = CCall v30, :String#==@0x1038, v31
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, ===@0x1008, cme:0x1010)
          v30:StringSubclass[class_exact:C] = GuardType v16, StringSubclass[class_exact:C]
          v31:String = GuardType v18, String
          v32:BoolExact = CCall v30, :String#==@0x1038, v31
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v2:BasicObject = GetLocal :l, l0, SP@5
          v3:BasicObject = GetLocal :r, l0, SP@4
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject):
          v16:BasicObject = GetLocal :l, l0, EP@4
          v18:BasicObject = GetLocal :r, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, ===@0x1008, cme:0x1010)
          v30:StringExact = GuardType v16, StringExact
          v31:String = GuardType v18, String
          v32:BoolExact = CCall v30, :String#==@0x1038, v31
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v32
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, size@0x1008, cme:0x1010)
          v24:StringExact = GuardType v13, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v26:Fixnum = CCall v24, :String#size@0x1038
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
       assert_snapshot!(hir_string("test"), @r"
       fn test@<compiled>:3:
       bb0():
         EntryPoint interpreter
         v1:BasicObject = LoadSelf
         v2:BasicObject = GetLocal :s, l0, SP@4
         Jump bb2(v1, v2)
       bb1(v5:BasicObject, v6:BasicObject):
         EntryPoint JIT(0)
         Jump bb2(v5, v6)
       bb2(v8:BasicObject, v9:BasicObject):
         v13:BasicObject = GetLocal :s, l0, EP@3
         PatchPoint NoSingletonClass(String@0x1000)
         PatchPoint MethodRedefined(String@0x1000, size@0x1008, cme:0x1010)
         v28:StringExact = GuardType v13, StringExact
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, bytesize@0x1008, cme:0x1010)
          v25:StringExact = GuardType v13, StringExact
          v26:CInt64 = LoadField v25, :len@0x1038
          v27:Fixnum = BoxFixnum v26
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v27
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, bytesize@0x1008, cme:0x1010)
          v29:StringExact = GuardType v13, StringExact
          v30:CInt64 = LoadField v29, :len@0x1038
          v31:Fixnum = BoxFixnum v30
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v21:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v21
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, length@0x1008, cme:0x1010)
          v24:StringExact = GuardType v13, StringExact
          IncrCounter inline_cfunc_optimized_send_count
          v26:Fixnum = CCall v24, :String#length@0x1038
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v29:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v18:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, ===@0x1018, cme:0x1020)
          v33:BoolExact = IsA v18, v29
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
        ");
    }

    #[test]
    fn test_dont_specialize_module_eqq() {
        eval(r#"
            def test(o) = Kernel === o
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Kernel)
          v29:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v18:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(Module@0x1010)
          PatchPoint MethodRedefined(Module@0x1010, ===@0x1018, cme:0x1020)
          IncrCounter inline_cfunc_optimized_send_count
          v34:BoolExact = CCall v29, :Module#===@0x1048, v18
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_specialize_is_a_class() {
        eval(r#"
            def test(o) = o.is_a?(String)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v29:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, is_a?@0x1009, cme:0x1010)
          v33:StringExact = GuardType v13, StringExact
          v34:BoolExact = IsA v33, v29
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_dont_specialize_is_a_module() {
        eval(r#"
            def test(o) = o.is_a?(Kernel)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Kernel)
          v29:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, is_a?@0x1018, cme:0x1020)
          v33:StringExact = GuardType v13, StringExact
          v34:BasicObject = CCallWithFrame v33, :Kernel#is_a?@0x1048, v29
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Integer)
          v33:Class[Integer@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, is_a?@0x1018, cme:0x1020)
          v37:StringExact = GuardType v13, StringExact
          v38:BoolExact = IsA v37, v33
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v26:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v26
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Integer)
          v33:Class[Integer@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v18:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(Class@0x1010)
          PatchPoint MethodRedefined(Class@0x1010, ===@0x1018, cme:0x1020)
          v37:BoolExact = IsA v18, v33
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v26:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v26
        ");
    }

    #[test]
    fn test_specialize_kind_of_class() {
        eval(r#"
            def test(o) = o.kind_of?(String)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, String)
          v29:Class[String@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1008)
          PatchPoint MethodRedefined(String@0x1008, kind_of?@0x1009, cme:0x1010)
          v33:StringExact = GuardType v13, StringExact
          v34:BoolExact = IsA v33, v29
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
        ");
    }

    #[test]
    fn test_dont_specialize_kind_of_module() {
        eval(r#"
            def test(o) = o.kind_of?(Kernel)
            test("asdf")
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:2:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Kernel)
          v29:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, kind_of?@0x1018, cme:0x1020)
          v33:StringExact = GuardType v13, StringExact
          v34:BasicObject = CCallWithFrame v33, :Kernel#kind_of?@0x1048, v29
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v34
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Integer)
          v33:Class[Integer@0x1008] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, kind_of?@0x1018, cme:0x1020)
          v37:StringExact = GuardType v13, StringExact
          v38:BoolExact = IsA v37, v33
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          v26:Fixnum[5] = Const Value(5)
          CheckInterrupts
          Return v26
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
          v11:Fixnum[1] = Const Value(1)
          IncrCounter complex_arg_pass_param_rest
          IncrCounter complex_arg_pass_param_block
          IncrCounter complex_arg_pass_param_kwrest
          v13:BasicObject = SendWithoutBlock v6, :fancy, v11 # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(test)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          IncrCounter complex_arg_pass_param_forwardable
          v11:BasicObject = SendWithoutBlock v6, :forwardable # SendFallbackReason: Complex argument passing
          PatchPoint NoEPEscape(call_forwardable)
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
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          PatchPoint NoSingletonClass(String@0x1000)
          PatchPoint MethodRedefined(String@0x1000, length@0x1008, cme:0x1010)
          v28:StringExact = GuardType v13, StringExact
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          v46:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v50:Class[C@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(initialize)
          v15:StaticSymbol[:_lex_actions] = Const Value(VALUE(0x1038))
          v17:TrueClass = Const Value(true)
          PatchPoint NoSingletonClass(Class@0x1040)
          PatchPoint MethodRedefined(Class@0x1040, respond_to?@0x1048, cme:0x1050)
          PatchPoint NoSingletonClass(Class@0x1040)
          PatchPoint MethodRedefined(Class@0x1040, _lex_actions@0x1078, cme:0x1080)
          v58:TrueClass = Const Value(true)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(initialize)
          CheckInterrupts
          v30:StaticSymbol[:CORRECT] = Const Value(VALUE(0x10a8))
          CheckInterrupts
          Return v30
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
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          v28:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v32:Class[C@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(Class@0x1038)
          PatchPoint MethodRedefined(Class@0x1038, name@0x1040, cme:0x1048)
          IncrCounter inline_cfunc_optimized_send_count
          v38:StringExact|NilClass = CCall v32, :Module#name@0x1070
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v38
        ");
    }

    #[test]
    fn test_fold_kernel_class() {
        eval(r#"
            class C; end
            def test(o) = o.class
            test(C.new)
        "#);
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, class@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:C] = GuardType v13, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v28:Class[C@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v28
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v10:Fixnum[5] = Const Value(5)
          PatchPoint MethodRedefined(Integer@0x1000, class@0x1008, cme:0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v23:Class[Integer@0x1000] = Const Value(VALUE(0x1000))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(Object@0x1000)
          PatchPoint MethodRedefined(Object@0x1000, class@0x1008, cme:0x1010)
          v20:HeapObject[class_exact*:Object@VALUE(0x1000)] = GuardType v6, HeapObject[class_exact*:Object@VALUE(0x1000)]
          IncrCounter inline_iseq_optimized_send_count
          v24:Class[Object@0x1038] = Const Value(VALUE(0x1038))
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v24
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
       assert_snapshot!(hir_string("read_nil_local"), @r"
       fn read_nil_local@<compiled>:3:
       bb0():
         EntryPoint interpreter
         v1:BasicObject = LoadSelf
         v2:BasicObject = GetLocal :a, l0, SP@7
         v3:BasicObject = GetLocal :_b, l0, SP@6
         v4:BasicObject = GetLocal :_c, l0, SP@5
         v5:NilClass = Const Value(nil)
         Jump bb2(v1, v2, v3, v4, v5)
       bb1(v8:BasicObject, v9:BasicObject, v10:BasicObject, v11:BasicObject):
         EntryPoint JIT(0)
         v12:NilClass = Const Value(nil)
         Jump bb2(v8, v9, v10, v11, v12)
       bb2(v14:BasicObject, v15:BasicObject, v16:BasicObject, v17:BasicObject, v18:NilClass):
         v22:BasicObject = GetLocal :formatted, l0, EP@3
         CheckInterrupts
         v25:CBool = Test v22
         v26:Truthy = RefineType v22, Truthy
         IfTrue v25, bb3(v14, v15, v16, v17, v26)
         v30:BasicObject = GetLocal :a, l0, EP@6
         SetLocal :formatted, l0, EP@3, v30
         Jump bb3(v14, v30, v16, v17, v30)
       bb3(v34:BasicObject, v35:BasicObject, v36:BasicObject, v37:BasicObject, v38:BasicObject):
         v42:BasicObject = GetLocal :formatted, l0, EP@3
         PatchPoint SingleRactorMode
         v56:HeapBasicObject = GuardType v34, HeapBasicObject
         v57:CShape = LoadField v56, :_shape_id@0x1000
         v58:CShape[0x1001] = GuardBitEquals v57, CShape(0x1001)
         StoreField v56, :@formatted@0x1002, v42
         WriteBarrier v56, v42
         v61:CShape[0x1003] = Const CShape(0x1003)
         StoreField v56, :_shape_id@0x1000, v61
         v49:Class[VMFrozenCore] = Const Value(VALUE(0x1008))
         PatchPoint NoSingletonClass(Class@0x1010)
         PatchPoint MethodRedefined(Class@0x1010, lambda@0x1018, cme:0x1020)
         v66:BasicObject = CCallWithFrame v49, :RubyVM::FrozenCore.lambda@0x1048, block=0x1050
         CheckInterrupts
         Return v66
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_OBJ)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestFrozen@0x1010)
          PatchPoint MethodRedefined(TestFrozen@0x1010, a@0x1018, cme:0x1020)
          v33:Fixnum[1] = Const Value(1)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, MULTI_FROZEN)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestMultiIvars@0x1010)
          PatchPoint MethodRedefined(TestMultiIvars@0x1010, b@0x1018, cme:0x1020)
          v33:Fixnum[20] = Const Value(20)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_STR)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestFrozenStr@0x1010)
          PatchPoint MethodRedefined(TestFrozenStr@0x1010, name@0x1018, cme:0x1020)
          v33:StringExact[VALUE(0x1048)] = Const Value(VALUE(0x1048))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_NIL)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestFrozenNil@0x1010)
          PatchPoint MethodRedefined(TestFrozenNil@0x1010, value@0x1018, cme:0x1020)
          v33:NilClass = Const Value(nil)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, UNFROZEN_OBJ)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestUnfrozen@0x1010)
          PatchPoint MethodRedefined(TestUnfrozen@0x1010, a@0x1018, cme:0x1020)
          v29:CShape = LoadField v24, :_shape_id@0x1048
          v30:CShape[0x1049] = GuardBitEquals v29, CShape(0x1049)
          v31:BasicObject = LoadField v24, :@a@0x104a
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v31
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_READER)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestAttrReader@0x1010)
          PatchPoint MethodRedefined(TestAttrReader@0x1010, value@0x1018, cme:0x1020)
          v33:Fixnum[42] = Const Value(42)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_SYM)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestFrozenSym@0x1010)
          PatchPoint MethodRedefined(TestFrozenSym@0x1010, sym@0x1018, cme:0x1020)
          v33:StaticSymbol[:hello] = Const Value(VALUE(0x1048))
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, FROZEN_TRUE)
          v24:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestFrozenBool@0x1010)
          PatchPoint MethodRedefined(TestFrozenBool@0x1010, flag@0x1018, cme:0x1020)
          v33:TrueClass = Const Value(true)
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v33
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:9:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :obj, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :obj, l0, EP@3
          PatchPoint NoSingletonClass(TestDynamic@0x1000)
          PatchPoint MethodRedefined(TestDynamic@0x1000, val@0x1008, cme:0x1010)
          v24:HeapObject[class_exact:TestDynamic] = GuardType v13, HeapObject[class_exact:TestDynamic]
          v27:CShape = LoadField v24, :_shape_id@0x1038
          v28:CShape[0x1039] = GuardBitEquals v27, CShape(0x1039)
          v29:BasicObject = LoadField v24, :@val@0x103a
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, NESTED_FROZEN)
          v36:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestNestedAccess@0x1010)
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, x@0x1018, cme:0x1020)
          v61:Fixnum[100] = Const Value(100)
          PatchPoint NoEPEscape(test)
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1048, NESTED_FROZEN)
          v42:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(TestNestedAccess@0x1010)
          PatchPoint MethodRedefined(TestNestedAccess@0x1010, y@0x1050, cme:0x1058)
          v63:Fixnum[200] = Const Value(200)
          PatchPoint NoEPEscape(test)
          PatchPoint MethodRedefined(Integer@0x1080, +@0x1088, cme:0x1090)
          v64:Fixnum[300] = Const Value(300)
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v64
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
          v24:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          PatchPoint NoSingletonClass(String@0x1010)
          PatchPoint MethodRedefined(String@0x1010, bytesize@0x1018, cme:0x1020)
          v28:CInt64 = LoadField v24, :len@0x1048
          v29:Fixnum = BoxFixnum v28
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v29
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, secret@0x1008, cme:0x1010)
          v20:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[42] = Const Value(42)
          PatchPoint NoEPEscape(callprivate)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v25:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:BasicObject = SendWithoutBlock v25, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(BasicObject@0x1000)
          PatchPoint MethodRedefined(BasicObject@0x1000, initialize@0x1008, cme:0x1010)
          v22:BasicObjectExact = GuardType v6, BasicObjectExact
          v23:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(callprivate)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v25:BasicObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:BasicObject = SendWithoutBlock v25, :initialize # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v25:ObjectExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:BasicObject = SendWithoutBlock v25, :toplevel_method # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v15
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, secret@0x1008, cme:0x1010)
          v20:HeapObject[class_exact:C] = GuardType v6, HeapObject[class_exact:C]
          IncrCounter inline_iseq_optimized_send_count
          v23:Fixnum[42] = Const Value(42)
          PatchPoint NoEPEscape(callprotected)
          CheckInterrupts
          Return v23
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1000, Obj)
          v25:HeapObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
          PatchPoint NoEPEscape(test)
          v15:BasicObject = SendWithoutBlock v25, :secret # SendFallbackReason: SendWithoutBlock: method private or protected and no FCALL
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v15
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :s, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :s, l0, EP@3
          v16:BasicObject = SendWithoutBlock v13, :length # SendFallbackReason: Singleton class previously created for receiver class
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(A@0x1000, foo@0x1008, cme:0x1010)
          v19:CPtr = GetLEP
          v20:RubyValue = LoadField v19, :_ep_method_entry@0x1038
          v21:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v20, Value(VALUE(0x1040))
          v22:RubyValue = LoadField v19, :_ep_specval@0x1048
          v23:FalseClass = GuardBitEquals v22, Value(false)
          v24:BasicObject = SendDirect v6, 0x1050, :foo (0x1060)
          PatchPoint NoEPEscape(foo)
          CheckInterrupts
          Return v24
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:BasicObject = GetLocal :x, l0, EP@3
          PatchPoint MethodRedefined(A@0x1000, foo@0x1008, cme:0x1010)
          v29:CPtr = GetLEP
          v30:RubyValue = LoadField v29, :_ep_method_entry@0x1038
          v31:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v30, Value(VALUE(0x1040))
          v32:RubyValue = LoadField v29, :_ep_specval@0x1048
          v33:FalseClass = GuardBitEquals v32, Value(false)
          v34:BasicObject = SendDirect v8, 0x1050, :foo (0x1060), v14
          PatchPoint NoEPEscape(foo)
          v20:Fixnum[1] = Const Value(1)
          PatchPoint MethodRedefined(Integer@0x1068, +@0x1070, cme:0x1078)
          v37:Fixnum = GuardType v34, Fixnum
          v38:Fixnum = FixnumAdd v37, v20
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v38
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

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:ArrayExact = GetLocal :x, l0, SP@4, *
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:ArrayExact):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:ArrayExact):
          v14:BasicObject = GetLocal :x, l0, EP@3
          v16:ArrayExact = ToArray v14
          PatchPoint NoEPEscape(foo)
          v20:BasicObject = InvokeSuper v8, 0x1000, v16 # SendFallbackReason: super: complex argument passing to `super` call
          PatchPoint NoEPEscape(foo)
          CheckInterrupts
          Return v20
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          v11:BasicObject = InvokeSuper v6, 0x1000 # SendFallbackReason: super: call made with a block
          PatchPoint NoEPEscape(foo)
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(Hash@0x1000, size@0x1008, cme:0x1010)
          v19:CPtr = GetLEP
          v20:RubyValue = LoadField v19, :_ep_method_entry@0x1038
          v21:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v20, Value(VALUE(0x1040))
          v22:RubyValue = LoadField v19, :_ep_specval@0x1048
          v23:FalseClass = GuardBitEquals v22, Value(false)
          IncrCounter inline_cfunc_optimized_send_count
          v25:Fixnum = CCall v6, :Hash#size@0x1050
          PatchPoint NoEPEscape(size)
          CheckInterrupts
          Return v25
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          Jump bb2(v1)
        bb1(v4:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v4)
        bb2(v6:BasicObject):
          PatchPoint MethodRedefined(BasicObject@0x1000, initialize@0x1008, cme:0x1010)
          v19:CPtr = GetLEP
          v20:RubyValue = LoadField v19, :_ep_method_entry@0x1038
          v21:CallableMethodEntry[VALUE(0x1040)] = GuardBitEquals v20, Value(VALUE(0x1040))
          v22:RubyValue = LoadField v19, :_ep_specval@0x1048
          v23:FalseClass = GuardBitEquals v22, Value(false)
          v24:NilClass = Const Value(nil)
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(initialize)
          CheckInterrupts
          Return v24
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
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :needle, l0, SP@5
          v3:BasicObject = GetLocal :offset, l0, SP@4
          v4:CPtr = LoadPC
          v5:CPtr[CPtr(0x1000)] = Const CPtr(0x1008)
          v6:CBool = IsBitEqual v4, v5
          IfTrue v6, bb2(v1, v2, v3)
          Jump bb4(v1, v2, v3)
        bb1(v10:BasicObject, v11:BasicObject):
          EntryPoint JIT(0)
          v12:NilClass = Const Value(nil)
          Jump bb2(v10, v11, v12)
        bb2(v19:BasicObject, v20:BasicObject, v21:BasicObject):
          v24:Fixnum[0] = Const Value(0)
          Jump bb4(v19, v20, v24)
        bb3(v15:BasicObject, v16:BasicObject, v17:BasicObject):
          EntryPoint JIT(1)
          Jump bb4(v15, v16, v17)
        bb4(v27:BasicObject, v28:BasicObject, v29:BasicObject):
          v34:BasicObject = GetLocal :needle, l0, EP@4
          v36:BasicObject = GetLocal :offset, l0, EP@3
          PatchPoint MethodRedefined(String@0x1010, byteindex@0x1018, cme:0x1020)
          v46:CPtr = GetLEP
          v47:RubyValue = LoadField v46, :_ep_method_entry@0x1048
          v48:CallableMethodEntry[VALUE(0x1050)] = GuardBitEquals v47, Value(VALUE(0x1050))
          v49:RubyValue = LoadField v46, :_ep_specval@0x1058
          v50:FalseClass = GuardBitEquals v49, Value(false)
          v51:BasicObject = CCallVariadic v27, :String#byteindex@0x1060, v34, v36
          PatchPoint NoEPEscape(byteindex)
          CheckInterrupts
          Return v51
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

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :blk, l0, SP@5
          v3:NilClass = Const Value(nil)
          Jump bb2(v1, v2, v3)
        bb1(v6:BasicObject, v7:BasicObject):
          EntryPoint JIT(0)
          v8:NilClass = Const Value(nil)
          Jump bb2(v6, v7, v8)
        bb2(v10:BasicObject, v11:BasicObject, v12:NilClass):
          PatchPoint NoSingletonClass(B@0x1000)
          PatchPoint MethodRedefined(B@0x1000, proc@0x1008, cme:0x1010)
          v33:HeapObject[class_exact:B] = GuardType v10, HeapObject[class_exact:B]
          v34:BasicObject = CCallWithFrame v33, :Kernel#proc@0x1038, block=0x1040
          SetLocal :other_block, l0, EP@3, v34
          v23:BasicObject = GetLocal :other_block, l0, EP@3
          v25:BasicObject = InvokeSuper v10, 0x1048, v23 # SendFallbackReason: super: complex argument passing to `super` call
          CheckInterrupts
          Return v25
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

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:10:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :items, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v14:BasicObject = GetLocal :items, l0, EP@3
          v16:StaticSymbol[:succ] = Const Value(VALUE(0x1000))
          v18:BasicObject = InvokeSuper v8, 0x1008, v14, v16 # SendFallbackReason: super: complex argument passing to `super` call
          PatchPoint NoEPEscape(foo)
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

        assert_snapshot!(hir, @r"
        fn foo@<compiled>:9:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :content, l0, SP@4
          v3:CPtr = LoadPC
          v4:CPtr[CPtr(0x1000)] = Const CPtr(0x1008)
          v5:CBool = IsBitEqual v3, v4
          IfTrue v5, bb2(v1, v2)
          Jump bb4(v1, v2)
        bb1(v9:BasicObject):
          EntryPoint JIT(0)
          v10:NilClass = Const Value(nil)
          Jump bb2(v9, v10)
        bb2(v16:BasicObject, v17:BasicObject):
          v20:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
          v21:StringExact = StringCopy v20
          Jump bb4(v16, v21)
        bb3(v13:BasicObject, v14:BasicObject):
          EntryPoint JIT(1)
          Jump bb4(v13, v14)
        bb4(v24:BasicObject, v25:BasicObject):
          v30:BasicObject = GetLocal :content, l0, EP@3
          v32:BasicObject = InvokeSuper v24, 0x1018, v30 # SendFallbackReason: super: complex argument passing to `super` call
          PatchPoint NoEPEscape(foo)
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :x, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :x, l0, EP@3
          CheckInterrupts
          v16:CBool = Test v13
          v17:Falsy = RefineType v13, Falsy
          IfFalse v16, bb5(v8, v17)
          v19:Truthy = RefineType v13, Truthy
          CheckInterrupts
          v27:Truthy = RefineType v19, Truthy
          CheckInterrupts
          v35:Truthy = RefineType v27, Truthy
          v38:Fixnum[3] = Const Value(3)
          CheckInterrupts
          Return v38
        bb5(v43:BasicObject, v44:Falsy):
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:11:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:CBool = HasType v13, HeapObject[class_exact:C]
          IfTrue v15, bb4(v8, v13, v13)
          v24:CBool = HasType v13, HeapObject[class_exact:D]
          IfTrue v24, bb5(v8, v13, v13)
          v33:BasicObject = SendWithoutBlock v13, :foo # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb3(v8, v13, v33)
        bb4(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
          IncrCounter inline_iseq_optimized_send_count
          v55:Fixnum[3] = Const Value(3)
          Jump bb3(v16, v17, v55)
        bb5(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          PatchPoint NoSingletonClass(D@0x1038)
          PatchPoint MethodRedefined(D@0x1038, foo@0x1008, cme:0x1040)
          IncrCounter inline_iseq_optimized_send_count
          v57:Fixnum[4] = Const Value(4)
          Jump bb3(v25, v26, v57)
        bb3(v35:BasicObject, v36:BasicObject, v37:BasicObject):
          v40:Fixnum[2] = Const Value(2)
          PatchPoint MethodRedefined(Integer@0x1068, +@0x1070, cme:0x1078)
          v60:Fixnum = GuardType v37, Fixnum
          v61:Fixnum = FixnumAdd v60, v40
          IncrCounter inline_cfunc_optimized_send_count
          CheckInterrupts
          Return v61
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
        assert_snapshot!(hir_string("test"), @r"
        fn test@<compiled>:5:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :o, l0, SP@4
          Jump bb2(v1, v2)
        bb1(v5:BasicObject, v6:BasicObject):
          EntryPoint JIT(0)
          Jump bb2(v5, v6)
        bb2(v8:BasicObject, v9:BasicObject):
          v13:BasicObject = GetLocal :o, l0, EP@3
          v15:CBool = HasType v13, HeapObject[class_exact:C]
          IfTrue v15, bb4(v8, v13, v13)
          v24:CBool = HasType v13, Fixnum
          IfTrue v24, bb5(v8, v13, v13)
          v33:BasicObject = SendWithoutBlock v13, :itself # SendFallbackReason: SendWithoutBlock: polymorphic fallback
          Jump bb3(v8, v13, v33)
        bb4(v16:BasicObject, v17:BasicObject, v18:BasicObject):
          v20:HeapObject[class_exact:C] = RefineType v18, HeapObject[class_exact:C]
          PatchPoint NoSingletonClass(C@0x1000)
          PatchPoint MethodRedefined(C@0x1000, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          Jump bb3(v16, v17, v20)
        bb5(v25:BasicObject, v26:BasicObject, v27:BasicObject):
          v29:Fixnum = RefineType v27, Fixnum
          PatchPoint MethodRedefined(Integer@0x1038, itself@0x1008, cme:0x1010)
          IncrCounter inline_cfunc_optimized_send_count
          Jump bb3(v25, v26, v29)
        bb3(v35:BasicObject, v36:BasicObject, v37:BasicObject):
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
          v49:HeapBasicObject = GuardType v6, HeapBasicObject
          v50:CShape = LoadField v49, :_shape_id@0x1000
          v51:CShape[0x1001] = GuardBitEquals v50, CShape(0x1001)
          StoreField v49, :@a@0x1002, v10
          WriteBarrier v49, v10
          v54:CShape[0x1003] = Const CShape(0x1003)
          StoreField v49, :_shape_id@0x1000, v54
          v14:HeapBasicObject = RefineType v6, HeapBasicObject
          PatchPoint NoEPEscape(test)
          v19:Fixnum[2] = Const Value(2)
          PatchPoint SingleRactorMode
          v57:CShape = LoadField v14, :_shape_id@0x1000
          v58:CShape[0x1003] = GuardBitEquals v57, CShape(0x1003)
          StoreField v14, :@b@0x1004, v19
          WriteBarrier v14, v19
          v61:CShape[0x1005] = Const CShape(0x1005)
          StoreField v14, :_shape_id@0x1000, v61
          v23:HeapBasicObject = RefineType v14, HeapBasicObject
          PatchPoint NoEPEscape(test)
          v28:Fixnum[3] = Const Value(3)
          PatchPoint SingleRactorMode
          v64:CShape = LoadField v23, :_shape_id@0x1000
          v65:CShape[0x1005] = GuardBitEquals v64, CShape(0x1005)
          StoreField v23, :@c@0x1006, v28
          WriteBarrier v23, v28
          v68:CShape[0x1007] = Const CShape(0x1007)
          StoreField v23, :_shape_id@0x1000, v68
          v32:HeapBasicObject = RefineType v23, HeapBasicObject
          PatchPoint NoEPEscape(test)
          v37:Fixnum[4] = Const Value(4)
          PatchPoint SingleRactorMode
          IncrCounter setivar_fallback_new_shape_needs_extension
          SetIvar v32, :@d, v37
          PatchPoint NoEPEscape(test)
          CheckInterrupts
          Return v37
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
        assert_snapshot!(hir_string("test_ep_escape"), @r"
        fn test_ep_escape@<compiled>:3:
        bb0():
          EntryPoint interpreter
          v1:BasicObject = LoadSelf
          v2:BasicObject = GetLocal :list, l0, SP@7
          v3:BasicObject = GetLocal :sep, l0, SP@6
          v4:BasicObject = GetLocal :iter_method, l0, SP@5
          v5:NilClass = Const Value(nil)
          v6:CPtr = LoadPC
          v7:CPtr[CPtr(0x1000)] = Const CPtr(0x1008)
          v8:CBool = IsBitEqual v6, v7
          IfTrue v8, bb2(v1, v2, v3, v4, v5)
          v10:CPtr[CPtr(0x1000)] = Const CPtr(0x1008)
          v11:CBool = IsBitEqual v6, v10
          IfTrue v11, bb4(v1, v2, v3, v4, v5)
          Jump bb6(v1, v2, v3, v4, v5)
        bb1(v15:BasicObject, v16:BasicObject):
          EntryPoint JIT(0)
          v17:NilClass = Const Value(nil)
          v18:NilClass = Const Value(nil)
          v19:NilClass = Const Value(nil)
          Jump bb2(v15, v16, v17, v18, v19)
        bb2(v35:BasicObject, v36:BasicObject, v37:BasicObject, v38:BasicObject, v39:NilClass):
          v42:NilClass = Const Value(nil)
          SetLocal :sep, l0, EP@5, v42
          Jump bb4(v35, v36, v42, v38, v39)
        bb3(v22:BasicObject, v23:BasicObject, v24:BasicObject):
          EntryPoint JIT(1)
          v25:NilClass = Const Value(nil)
          v26:NilClass = Const Value(nil)
          Jump bb4(v22, v23, v24, v25, v26)
        bb4(v46:BasicObject, v47:BasicObject, v48:BasicObject, v49:BasicObject, v50:NilClass):
          v53:StaticSymbol[:each] = Const Value(VALUE(0x1010))
          SetLocal :iter_method, l0, EP@4, v53
          Jump bb6(v46, v47, v48, v53, v50)
        bb5(v29:BasicObject, v30:BasicObject, v31:BasicObject, v32:BasicObject):
          EntryPoint JIT(2)
          v33:NilClass = Const Value(nil)
          Jump bb6(v29, v30, v31, v32, v33)
        bb6(v57:BasicObject, v58:BasicObject, v59:BasicObject, v60:BasicObject, v61:NilClass):
          v65:BasicObject = GetLocal :sep, l0, EP@5
          CheckInterrupts
          v68:CBool = Test v65
          v69:Truthy = RefineType v65, Truthy
          IfTrue v68, bb7(v57, v58, v69, v60, v61)
          v71:Falsy = RefineType v65, Falsy
          PatchPoint NoSingletonClass(Object@0x1018)
          PatchPoint MethodRedefined(Object@0x1018, lambda@0x1020, cme:0x1028)
          v107:HeapObject[class_exact*:Object@VALUE(0x1018)] = GuardType v57, HeapObject[class_exact*:Object@VALUE(0x1018)]
          v108:BasicObject = CCallWithFrame v107, :Kernel#lambda@0x1050, block=0x1058
          SetLocal :sep, l0, EP@5, v108
          Jump bb7(v57, v58, v108, v60, v61)
        bb7(v78:BasicObject, v79:BasicObject, v80:BasicObject, v81:BasicObject, v82:NilClass):
          PatchPoint SingleRactorMode
          PatchPoint StableConstantNames(0x1060, CONST)
          v103:HashExact[VALUE(0x1068)] = Const Value(VALUE(0x1068))
          SetLocal :kwsplat, l0, EP@3, v103
          v92:BasicObject = GetLocal :list, l0, EP@6
          v94:BasicObject = GetLocal :iter_method, l0, EP@4
          v96:BasicObject = Send v92, 0x1070, :__send__, v94 # SendFallbackReason: Send: unsupported method type Optimized
          CheckInterrupts
          Return v96
        ");
    }

    #[test]
    fn test_array_each() {
        eval("[1, 2, 3].each { |x| x }");
        assert_snapshot!(hir_string_proc("Array.instance_method(:each)"), @r"
        fn each@<internal:array>:
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
          v15:TrueClass|NilClass = Defined yield, v13
          v17:CBool = Test v15
          IfFalse v17, bb3(v8, v9)
          v37:Fixnum[0] = Const Value(0)
          Jump bb7(v8, v37)
        bb3(v23:BasicObject, v24:NilClass):
          v28:BasicObject = InvokeBuiltin <inline_expr>, v23
          PatchPoint NoEPEscape(each)
          CheckInterrupts
          Return v28
        bb7(v50:BasicObject, v51:Fixnum):
          v91:Array = RefineType v50, Array
          v92:CInt64 = ArrayLength v91
          v93:Fixnum = BoxFixnum v92
          v94:BoolExact = FixnumGe v51, v93
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(each)
          v58:CBool = Test v94
          IfFalse v58, bb6(v50, v51)
          CheckInterrupts
          Return v50
        bb6(v71:BasicObject, v72:Fixnum):
          v96:Array = RefineType v71, Array
          v97:CInt64 = UnboxFixnum v72
          v98:BasicObject = ArrayAref v96, v97
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(each)
          v80:BasicObject = InvokeBlock, v98 # SendFallbackReason: Uncategorized(invokeblock)
          PatchPoint NoEPEscape(each)
          v100:Fixnum[1] = Const Value(1)
          v101:Fixnum = FixnumAdd v72, v100
          IncrCounter inline_cfunc_optimized_send_count
          PatchPoint NoEPEscape(each)
          Jump bb7(v71, v101)
        ");
    }
}
