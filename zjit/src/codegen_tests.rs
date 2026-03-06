#![cfg(test)]

use crate::codegen::MAX_ISEQ_VERSIONS;
use crate::cruby::*;
use crate::hir::tests::hir_build_tests::assert_contains_opcode;
use crate::payload::*;
use insta::assert_snapshot;

#[test]
fn test_call_itself() {
    assert_snapshot!(inspect("
        def test = 42.itself
        test
        test
    "), @"42");
}

#[test]
fn test_nil() {
    assert_snapshot!(inspect("
        def test = nil
        test
        test
    "), @"nil");
}

#[test]
fn test_putobject() {
    assert_snapshot!(inspect("
        def test = 1
        test
        test
    "), @"1");
}

#[test]
fn test_putstring() {
    eval(r##"
        def test = "#{""}"
        test
    "##);
    assert_contains_opcode("test", YARVINSN_putstring);
    assert_snapshot!(inspect(r##"test"##), @r#""""#);
}

#[test]
fn test_putchilledstring() {
    eval(r#"
        def test = ""
        test
    "#);
    assert_contains_opcode("test", YARVINSN_putchilledstring);
    assert_snapshot!(inspect(r#"test"#), @r#""""#);
}

#[test]
fn test_leave_param() {
    assert_snapshot!(inspect("
        def test(n) = n
        test(5)
        test(5)
    "), @"5");
}

#[test]
fn test_getglobal_with_warning() {
    eval(r#"
        Warning[:deprecated] = true

        module Warning
          def warn(message)
            raise
          end
        end

        def test
          $=
        rescue
          "rescued"
        end
        $VERBOSE = true
        test
    "#);
    assert_contains_opcode("test", YARVINSN_getglobal);
    assert_snapshot!(inspect(r#"test"#), @r#""rescued""#);
}

#[test]
fn test_setglobal() {
    eval("
        def test
          $a = 1
          $a
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_setglobal);
    assert_snapshot!(inspect("test"), @"1");
}

#[test]
fn test_string_intern() {
    eval(r#"
        def test
          :"foo#{123}"
        end
        test
    "#);
    assert_contains_opcode("test", YARVINSN_intern);
    assert_snapshot!(inspect(r#"test"#), @":foo123");
}

#[test]
fn test_duphash() {
    eval("
        def test
          {a: 1}
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_duphash);
    assert_snapshot!(inspect("test"), @"{a: 1}");
}

#[test]
fn test_pushtoarray() {
    eval("
        def test
          [*[], 1, 2, 3]
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_pushtoarray);
    assert_snapshot!(inspect("test"), @"[1, 2, 3]");
}

#[test]
fn test_splatarray_new_array() {
    eval("
        def test a
          [*a, 3]
        end
        test [1, 2]
    ");
    assert_contains_opcode("test", YARVINSN_splatarray);
    assert_snapshot!(inspect("test [1, 2]"), @"[1, 2, 3]");
}

#[test]
fn test_splatarray_existing_array() {
    eval("
        def foo v
          [1, 2, v]
        end
        def test a
          foo(*a)
        end
        test [3]
    ");
    assert_contains_opcode("test", YARVINSN_splatarray);
    assert_snapshot!(inspect("test [3]"), @"[1, 2, 3]");
}

#[test]
fn test_concattoarray() {
    eval("
        def test(*a)
          [1, 2, *a]
        end
        test 3
    ");
    assert_contains_opcode("test", YARVINSN_concattoarray);
    assert_snapshot!(inspect("test 3"), @"[1, 2, 3]");
}

#[test]
fn test_definedivar() {
    eval("
        def test
          v0 = defined?(@a)
          @a = nil
          v1 = defined?(@a)
          remove_instance_variable :@a
          v2 = defined?(@a)
          [v0, v1, v2]
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_definedivar);
    assert_snapshot!(inspect("test"), @r#"[nil, "instance-variable", nil]"#);
}

#[test]
fn test_setglobal_with_trace_var_exception() {
    eval(r#"
        def test
          $a = 1
        rescue
          "rescued"
        end
        trace_var(:$a) { raise }
        test
    "#);
    assert_contains_opcode("test", YARVINSN_setglobal);
    assert_snapshot!(inspect(r#"test"#), @r#""rescued""#);
}

#[test]
fn test_getlocal_after_eval() {
    assert_snapshot!(inspect("
        def test
          a = 1
          eval('a = 2')
          a
        end
        test
        test
    "), @"2");
}

#[test]
fn test_getlocal_after_instance_eval() {
    assert_snapshot!(inspect("
        def test
          a = 1
          instance_eval('a = 2')
          a
        end
        test
        test
    "), @"2");
}

#[test]
fn test_getlocal_after_module_eval() {
    assert_snapshot!(inspect("
        def test
          a = 1
          Kernel.module_eval('a = 2')
          a
        end
        test
        test
    "), @"2");
}

#[test]
fn test_getlocal_after_class_eval() {
    assert_snapshot!(inspect("
        def test
          a = 1
          Kernel.class_eval('a = 2')
          a
        end
        test
        test
    "), @"2");
}

#[test]
fn test_setlocal() {
    assert_snapshot!(inspect("
        def test(n)
          m = n
          m
        end
        test(3)
        test(3)
    "), @"3");
}

#[test]
fn test_return_nonparam_local() {
    assert_snapshot!(inspect("
        def foo(a)
          if false
            x = nil
          end
          x
        end
        def test = foo(1)
        test
        test
    "), @"nil");
}

#[test]
fn test_nonparam_local_nil_in_jit_call() {
    assert_snapshot!(inspect(r#"
        def f(a)
          a ||= 1
          if false; b = 1; end
          eval("-> { p 'x#{b}' }")
        end

        4.times.map { f(1).call }
    "#), @r#"["x", "x", "x", "x"]"#);
}

#[test]
fn test_kwargs_with_exit_and_local_invalidation() {
    assert_snapshot!(inspect(r#"
        def a(b:, c:)
          if c == :b
            return -> {}
          end
          Class # invalidate locals

          raise "c is :b!" if c == :b
        end

        def test
          # note opposite order of kwargs
          a(c: :c, b: :b)
        end

        4.times { test }
        :ok
    "#), @":ok");
}

#[test]
fn test_kwargs_with_max_direct_send_arg_count() {
    assert_snapshot!(inspect("
        def kwargs(five, six, a:, b:, c:, d:, e:, f:)
          [a, b, c, d, five, six, e, f]
        end

        5.times.flat_map do
          [
            kwargs(5, 6, d: 4, c: 3, a: 1, b: 2, e: 7, f: 8),
            kwargs(5, 6, d: 4, c: 3, b: 2, a: 1, e: 7, f: 8)
          ]
        end.uniq
    "), @"[[1, 2, 3, 4, 5, 6, 7, 8]]");
}

#[test]
fn test_setlocal_on_eval() {
    assert_snapshot!(inspect("
        @b = binding
        eval('a = 1', @b)
        eval('a', @b)
    "), @"1");
}

#[test]
fn test_optional_arguments() {
    assert_snapshot!(inspect("
        def test(a, b = 2, c = 3)
          [a, b, c]
        end
        [test(1), test(10, 20), test(100, 200, 300)]
    "), @"[[1, 2, 3], [10, 20, 3], [100, 200, 300]]");
}

#[test]
fn test_optional_arguments_setlocal() {
    assert_snapshot!(inspect("
        def test(a = (b = 2))
          [a, b]
        end
        [test, test(1)]
    "), @"[[2, 2], [1, nil]]");
}

#[test]
fn test_optional_arguments_cyclic() {
    assert_snapshot!(inspect("
        test = proc { |a=a| a }
        [test.call, test.call(1)]
    "), @"[nil, 1]");
}

#[test]
fn test_getblockparamproxy() {
    eval("
        def test(&block)
          0.then(&block)
        end
        test { 1 }
    ");
    assert_contains_opcode("test", YARVINSN_getblockparamproxy);
    assert_snapshot!(inspect("test { 1 }"), @"1");
}

#[test]
fn test_getblockparam() {
    eval("
        def test(&blk)
          blk
        end
        test { 2 }.call
    ");
    assert_contains_opcode("test", YARVINSN_getblockparam);
    assert_snapshot!(inspect("test { 2 }.call"), @"2");
}

#[test]
fn test_getblockparam_proxy_side_exit_restores_block_local() {
    eval("
        def test(&block)
          b = block
          raise \"test\" unless block
          b ? 2 : 3
        end
        test {}
    ");
    assert_contains_opcode("test", YARVINSN_getblockparam);
    assert_snapshot!(inspect("test {}"), @"2");
}

#[test]
fn test_getblockparam_used_twice_in_args() {
    eval("
        def f(*args) = args
        def test(&blk)
          b = blk
          f(*[1], blk)
          blk
        end
        test {1}.call
    ");
    assert_contains_opcode("test", YARVINSN_getblockparam);
    assert_snapshot!(inspect("test {1}.call"), @"1");
}

#[test]
fn test_optimized_method_call_proc_call() {
    eval("
        def test(p)
          p.call(1)
        end
        test(proc { |x| x * 2 })
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test(proc { |x| x * 2 })"), @"2");
}

#[test]
fn test_optimized_method_call_proc_aref() {
    eval("
        def test(p)
          p[2]
        end
        test(proc { |x| x * 2 })
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(proc { |x| x * 2 })"), @"4");
}

#[test]
fn test_optimized_method_call_proc_yield() {
    eval("
        def test(p)
          p.yield(3)
        end
        test(proc { |x| x * 2 })
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test(proc { |x| x * 2 })"), @"6");
}

#[test]
fn test_optimized_method_call_proc_kw_splat() {
    eval("
        def test(p, h)
          p.call(**h)
        end
        test(proc { |**kw| kw[:a] + kw[:b] }, { a: 1, b: 2 })
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test(proc { |**kw| kw[:a] + kw[:b] }, { a: 1, b: 2 })"), @"3");
}

#[test]
fn test_optimized_method_call_proc_call_splat() {
    assert_snapshot!(inspect("
        p = proc { |x| x + 1 }
        def test(p)
          ary = [42]
          p.call(*ary)
        end
        test(p)
        test(p)
    "), @"43");
}

#[test]
fn test_optimized_method_call_proc_call_kwarg() {
    assert_snapshot!(inspect("
        p = proc { |a:| a }
        def test(p)
          p.call(a: 1)
        end
        test(p)
        test(p)
    "), @"1");
}

#[test]
fn test_setlocal_on_eval_with_spill() {
    assert_snapshot!(inspect("
        @b = binding
        eval('a = 1; itself', @b)
        eval('a', @b)
    "), @"1");
}

#[test]
fn test_nested_local_access() {
    assert_snapshot!(inspect("
        1.times do |l2|
          1.times do |l1|
            define_method(:test) do
              l1 = 1
              l2 = 2
              l3 = 3
              [l1, l2, l3]
            end
          end
        end

        test
        test
        test
    "), @"[1, 2, 3]");
}

#[test]
fn test_send_with_local_written_by_blockiseq() {
    assert_snapshot!(inspect("
        def test
          l1 = nil
          l2 = nil
          tap do |_|
            l1 = 1
            tap do |_|
              l2 = 2
            end
          end

          [l1, l2]
        end

        test
        test
    "), @"[1, 2]");
}

#[test]
fn test_send_without_block() {
    assert_snapshot!(inspect("
        def foo = 1
        def bar(a) = a - 1
        def baz(a, b) = a - b

        def test1 = foo
        def test2 = bar(3)
        def test3 = baz(4, 1)

        [test1, test2, test3]
    "), @"[1, 2, 3]");
}

#[test]
fn test_send_with_six_args() {
    assert_snapshot!(inspect("
        def foo(a1, a2, a3, a4, a5, a6)
          [a1, a2, a3, a4, a5, a6]
        end

        def test
          foo(1, 2, 3, 4, 5, 6)
        end

        test # profile send
        test
    "), @"[1, 2, 3, 4, 5, 6]");
}

#[test]
fn test_send_optional_arguments() {
    assert_snapshot!(inspect("
        def test(a, b = 2) = [a, b]
        def entry = [test(1), test(3, 4)]
        entry
        entry
    "), @"[[1, 2], [3, 4]]");
}

#[test]
fn test_send_nil_block_arg() {
    assert_snapshot!(inspect("
        def test = block_given?
        def entry = test(&nil)
        test
        test
    "), @"false");
}

#[test]
fn test_send_symbol_block_arg() {
    assert_snapshot!(inspect("
        def test = [1, 2].map(&:to_s)
        test
        test
    "), @r#"["1", "2"]"#);
}

#[test]
fn test_send_variadic_with_block() {
    assert_snapshot!(inspect("
        A = [1, 2, 3]
        B = [\"a\", \"b\", \"c\"]

        def test
          result = []
          A.zip(B) { |x, y| result << [x, y] }
          result
        end

        test; test
    "), @r#"[[1, "a"], [2, "b"], [3, "c"]]"#);
}

#[test]
fn test_send_kwarg_optional() {
    assert_snapshot!(inspect("
        def test(a: 1, b: 2) = [a, b]
        def entry = test
        entry
        entry
    "), @"[1, 2]");
}

#[test]
fn test_send_kwarg_optional_too_many() {
    assert_snapshot!(inspect("
        def test(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10) = [a, b, c, d, e, f, g, h, i, j]
        def entry = test
        entry
        entry
    "), @"[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]");
}

#[test]
fn test_send_kwarg_required_and_optional() {
    assert_snapshot!(inspect("
        def test(a:, b: 2) = [a, b]
        def entry = test(a: 3)
        entry
        entry
    "), @"[3, 2]");
}

#[test]
fn test_send_kwarg_to_hash() {
    assert_snapshot!(inspect("
        def test(hash) = hash
        def entry = test(a: 3)
        entry
        entry
    "), @"{a: 3}");
}

#[test]
fn test_send_kwarg_to_ccall() {
    assert_snapshot!(inspect(r#"
        def test(s) = s.each_line(chomp: true).to_a
        def entry = test(%(a\nb\nc))
        entry
        entry
    "#), @r#"["a", "b", "c"]"#);
}

#[test]
fn test_send_kwarg_and_block_to_ccall() {
    assert_snapshot!(inspect(r#"
        def test(s)
          a = []
          s.each_line(chomp: true) { |l| a << l }
          a
        end
        def entry = test(%(a\nb\nc))
        entry
        entry
    "#), @r#"["a", "b", "c"]"#);
}

#[test]
fn test_send_kwarg_with_too_many_args_to_c_call() {
    assert_snapshot!(inspect(r#"
        def test(a:, b:, c:, d:, e:) = sprintf("%s %s %s %s %s", a, b, c, d, kwargs: e)
        def entry = test(e: :e, d: :d, c: :c, a: :a, b: :b)
        entry
        entry
    "#), @r#""a b c d {kwargs: :e}""#);
}

#[test]
fn test_send_kwsplat() {
    assert_snapshot!(inspect("
        def test(a:) = a
        def entry = test(**{a: 3})
        entry
        entry
    "), @"3");
}

#[test]
fn test_send_kwrest() {
    assert_snapshot!(inspect("
        def test(**kwargs) = kwargs
        def entry = test(a: 3)
        entry
        entry
    "), @"{a: 3}");
}

#[test]
fn test_send_req_kwreq() {
    assert_snapshot!(inspect("
        def test(a, c:) = [a, c]
        def entry = test(1, c: 3)
        entry
        entry
    "), @"[1, 3]");
}

#[test]
fn test_send_req_opt_kwreq() {
    assert_snapshot!(inspect("
        def test(a, b = 2, c:) = [a, b, c]
        def entry = [test(1, c: 3), test(-1, -2, c: -3)]
        entry
        entry
    "), @"[[1, 2, 3], [-1, -2, -3]]");
}

#[test]
fn test_send_req_opt_kwreq_kwopt() {
    assert_snapshot!(inspect("
        def test(a, b = 2, c:, d: 4) = [a, b, c, d]
        def entry = [test(1, c: 3), test(-1, -2, d: -4, c: -3)]
        entry
        entry
    "), @"[[1, 2, 3, 4], [-1, -2, -3, -4]]");
}

#[test]
fn test_send_unexpected_keyword() {
    assert_snapshot!(inspect("
        def test(a: 1) = a*2
        def entry
          test(z: 2)
        rescue ArgumentError
          :error
        end

        entry
        entry
    "), @":error");
}

#[test]
fn test_pos_optional_with_maybe_too_many_args() {
    assert_snapshot!(inspect("
        def target(a = 1, b = 2, c = 3, d = 4, e = 5, f:) = [a, b, c, d, e, f]
        def test = [target(f: 6), target(10, 20, 30, f: 6), target(10, 20, 30, 40, 50, f: 60)]
        test
        test
    "), @"[[1, 2, 3, 4, 5, 6], [10, 20, 30, 4, 5, 6], [10, 20, 30, 40, 50, 60]]");
}

#[test]
fn test_send_kwarg_partial_optional() {
    assert_snapshot!(inspect("
        def test(a: 1, b: 2, c: 3) = [a, b, c]
        def entry = [test, test(b: 20), test(c: 30, a: 10)]
        entry
        entry
    "), @"[[1, 2, 3], [1, 20, 3], [10, 2, 30]]");
}

#[test]
fn test_send_kwarg_optional_a_lot() {
    assert_snapshot!(inspect("
        def test(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6) = [a, b, c, d, e, f]
        def entry = [test, test(d: 7, f: 9, e: 8), test(f: 12, e: 10, d: 8, c: 6, b: 4, a: 2)]
        entry
        entry
    "), @"[[1, 2, 3, 4, 5, 6], [1, 2, 3, 7, 8, 9], [2, 4, 6, 8, 10, 12]]");
}

#[test]
fn test_send_kwarg_non_constant_default() {
    assert_snapshot!(inspect("
        def make_default = 2
        def test(a: 1, b: make_default) = [a, b]
        def entry = [test, test(a: 10)]
        entry
        entry
    "), @"[[1, 2], [10, 2]]");
}

#[test]
fn test_send_kwarg_optional_static_with_side_exit() {
    assert_snapshot!(inspect("
        def callee(a: 1, b: 2)
          x = binding.local_variable_get(:a)
          [a, b, x]
        end

        def entry
          callee(a: 10)
        end

        entry
        entry
    "), @"[10, 2, 10]");
}

#[test]
fn test_send_hash_to_kwarg_only_method() {
    assert_snapshot!(inspect(r#"
        def callee(a:) = a

        def entry
          callee({a: 1})
        rescue ArgumentError
          "ArgumentError"
        end

        entry
        entry
    "#), @r#""ArgumentError""#);
}

#[test]
fn test_send_hash_to_optional_kwarg_only_method() {
    assert_snapshot!(inspect(r#"
        def callee(a: nil) = a

        def entry
          callee({a: 1})
        rescue ArgumentError
          "ArgumentError"
        end

        entry
        entry
    "#), @r#""ArgumentError""#);
}

#[test]
fn test_send_all_arg_types() {
    assert_snapshot!(inspect("
        def test(a, b = :opt, c, d:, e: :kwo) = [a, b, c, d, e, block_given?]
        def entry = test(:req, :post, d: :kwr) {}
        entry
        entry
    "), @"[:req, :opt, :post, :kwr, :kwo, true]");
}

#[test]
fn test_send_ccall_variadic_with_different_receiver_classes() {
    assert_snapshot!(inspect(r#"
        def test(obj) = obj.start_with?("a")
        [test("abc"), test(:abc)]
    "#), @"[true, true]");
}

#[test]
fn test_forwardable_iseq() {
    assert_snapshot!(inspect("
        def test(...) = 1
        test
        test
    "), @"1");
}

#[test]
fn test_sendforward() {
    eval("
        def callee(a, b) = [a, b]
        def test(...) = callee(...)
        test(1, 2)
    ");
    assert_contains_opcode("test", YARVINSN_sendforward);
    assert_snapshot!(inspect("test(1, 2)"), @"[1, 2]");
}

#[test]
fn test_iseq_with_optional_arguments() {
    assert_snapshot!(inspect("
        def test(a, b = 2) = [a, b]
        [test(1), test(3, 4)]
    "), @"[[1, 2], [3, 4]]");
}

#[test]
fn test_invokesuper() {
    assert_snapshot!(inspect("
        class Foo
          def foo(a) = a + 1
          def bar(a) = a + 10
        end

        class Bar < Foo
          def foo(a) = super(a) + 2
          def bar(a) = super + 20
        end

        bar = Bar.new
        [bar.foo(3), bar.bar(30)]
    "), @"[6, 60]");
}

#[test]
fn test_invokesuper_to_iseq() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            "A"
          end
        end

        class B < A
          def foo
            ["B", super]
          end
        end

        def test
          B.new.foo
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["B", "A"]"#);
}

#[test]
fn test_invokesuper_with_args() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(x)
            x * 2
          end
        end

        class B < A
          def foo(x)
            ["B", super(x) + 1]
          end
        end

        def test
          B.new.foo(5)
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["B", 11]"#);
}

#[test]
fn test_invokesuper_with_args_to_rest_param() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(x, *rest)
            [x, rest]
          end
        end

        class B < A
          def foo(x, y, z)
            ["B", *super(x, y, z)]
          end
        end

        def test
          B.new.foo("a", "b", "c")
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["B", "a", ["b", "c"]]"#);
}

#[test]
fn test_invokesuper_with_block() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no_block"
          end
        end

        class B < A
          def foo
            ["B", super { "from_block" }]
          end
        end

        def test
          B.new.foo
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["B", "from_block"]"#);
}

#[test]
fn test_invokesuper_to_cfunc_no_args() {
    assert_snapshot!(inspect(r#"
        class MyString < String
          def length
            ["MyString", super]
          end
        end

        def test
          MyString.new("abc").length
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["MyString", 3]"#);
}

#[test]
fn test_invokesuper_to_cfunc_simple_args() {
    assert_snapshot!(inspect(r#"
        class MyString < String
          def include?(other)
            ["MyString", super(other)]
          end
        end

        def test
          MyString.new("abc").include?("bc")
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["MyString", true]"#);
}

#[test]
fn test_invokesuper_to_cfunc_with_optional_arg() {
    assert_snapshot!(inspect(r#"
        class MyString < String
          def byteindex(needle, offset = 0)
            ["MyString", super(needle, offset)]
          end
        end

        def test
          MyString.new("hello world").byteindex("world")
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["MyString", 6]"#);
}

#[test]
fn test_invokesuper_to_cfunc_varargs() {
    assert_snapshot!(inspect(r#"
        class MyString < String
          def end_with?(str)
            ["MyString", super(str)]
          end
        end

        def test
          MyString.new("abc").end_with?("bc")
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["MyString", true]"#);
}

#[test]
fn test_invokesuper_multilevel() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            "A"
          end
        end

        class B < A
          def foo
            ["B", super]
          end
        end

        class C < B
          def foo
            ["C", super]
          end
        end

        def test
          C.new.foo
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["C", ["B", "A"]]"#);
}

#[test]
fn test_invokesuper_forwards_block_implicitly() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no_block"
          end
        end

        class B < A
          def foo
            ["B", super]  # should forward the block from caller
          end
        end

        def test
          B.new.foo { "forwarded_block" }
        end

        test  # profile invokesuper
        test  # compile + run compiled code
    "#), @r#"["B", "forwarded_block"]"#);
}

#[test]
fn test_invokesuper_forwards_block_implicitly_with_args() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(x)
            [x, (block_given? ? yield : "no_block")]
          end
        end

        class B < A
          def foo(x)
            ["B", super(x)]  # explicit args, but block should still be forwarded
          end
        end

        def test
          B.new.foo("arg_value") { "forwarded" }
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", ["arg_value", "forwarded"]]"#);
}

#[test]
fn test_invokesuper_forwards_block_implicitly_no_block_given() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no_block"
          end
        end

        class B < A
          def foo
            ["B", super]  # no block given by caller
          end
        end

        def test
          B.new.foo  # called without a block
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", "no_block"]"#);
}

#[test]
fn test_invokesuper_forwards_block_implicitly_multilevel() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no_block"
          end
        end

        class B < A
          def foo
            ["B", super]  # forwards block to A
          end
        end

        class C < B
          def foo
            ["C", super]  # forwards block to B, which forwards to A
          end
        end

        def test
          C.new.foo { "deep_block" }
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["C", ["B", "deep_block"]]"#);
}

#[test]
fn test_invokesuper_forwards_block_param() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no_block"
          end
        end

        class B < A
          def foo(&block)
            ["B", super]  # should forward &block implicitly
          end
        end

        def test
          B.new.foo { "block_param_forwarded" }
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", "block_param_forwarded"]"#);
}

#[test]
fn test_invokesuper_with_blockarg() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            block_given? ? yield : "no block"
          end
        end

        class B < A
          def foo(&blk)
            other_block = proc { "different block" }
            ["B", super(&other_block)]
          end
        end

        def test
          B.new.foo { "passed block" }
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", "different block"]"#);
}

#[test]
fn test_invokesuper_with_symbol_to_proc() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(items, &blk)
            items.map(&blk)
          end
        end

        class B < A
          def foo(items)
            ["B", super(items, &:succ)]
          end
        end

        def test
          B.new.foo([2, 4, 6])
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", [3, 5, 7]]"#);
}

#[test]
fn test_invokesuper_with_splat() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(a, b, c)
            a + b + c
          end
        end

        class B < A
          def foo(*args)
            ["B", super(*args)]
          end
        end

        def test
          B.new.foo(1, 2, 3)
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", 6]"#);
}

#[test]
fn test_invokesuper_with_kwargs() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(x:, y:)
            "x=#{x}, y=#{y}"
          end
        end

        class B < A
          def foo(x:, y:)
            ["B", super(x: x, y: y)]
          end
        end

        def test
          B.new.foo(x: 1, y: 2)
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", "x=1, y=2"]"#);
}

#[test]
fn test_invokesuper_with_kw_splat() {
    assert_snapshot!(inspect(r#"
        class A
          def foo(x:, y:)
            "x=#{x}, y=#{y}"
          end
        end

        class B < A
          def foo(**kwargs)
            ["B", super(**kwargs)]
          end
        end

        def test
          B.new.foo(x: 1, y: 2)
        end

        test  # profile
        test  # compile + run compiled code
    "#), @r#"["B", "x=1, y=2"]"#);
}

#[test]
fn test_invokesuper_with_include() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            "A"
          end
        end

        class B < A
          def foo
            ["B", super]
          end
        end

        def test
          B.new.foo
        end

        test  # profile invokesuper (super -> A#foo)
        test  # compile with super -> A#foo

        # Now include a module in B that defines foo - super should go to M#foo instead
        module M
          def foo
            "M"
          end
        end
        B.include(M)

        test  # should call M#foo, not A#foo
    "#), @r#"["B", "M"]"#);
}

#[test]
fn test_invokesuper_with_prepend() {
    assert_snapshot!(inspect(r#"
        class A
          def foo
            "A"
          end
        end

        class B < A
          def foo
            ["B", super]
          end
        end

        def test
          B.new.foo
        end

        test  # profile invokesuper (super -> A#foo)
        test  # compile with super -> A#foo

        # Now prepend a module that defines foo - super should go to M#foo instead
        module M
          def foo
            "M"
          end
        end
        A.prepend(M)

        test  # should call M#foo, not A#foo
    "#), @r#"["B", "M"]"#);
}

#[test]
fn test_invokesuper_with_keyword_args() {
    assert_snapshot!(inspect(r#"
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

        def test
          B.new.foo("image data")
        end

        test
        test
    "#), @r#"{content: "image data"}"#);
}

#[test]
fn test_invokesuper_with_optional_keyword_args() {
    assert_snapshot!(inspect("
        class Parent
          def foo(a, b: 2, c: 3) = [a, b, c]
        end

        class Child < Parent
          def foo(a) = super(a)
        end

        def test = Child.new.foo(1)

        test
        test
    "), @"[1, 2, 3]");
}

#[test]
fn test_invokesuperforward() {
    assert_snapshot!(inspect("
        class A
          def foo(a,b,c) = [a,b,c]
        end

        class B < A
          def foo(...) = super
        end

        def test
          B.new.foo(1, 2, 3)
        end

        test
        test
    "), @"[1, 2, 3]");
}

#[test]
fn test_invokesuperforward_with_args_kwargs_and_block() {
    assert_snapshot!(inspect("
        class A
          def foo(*args, **kwargs, &block)
            [args, kwargs, block&.call]
          end
        end

        class B < A
          def foo(...) = super
        end

        def test
          B.new.foo(1, 2, x: 3) { 4 }
        end

        test
        test
    "), @"[[1, 2], {x: 3}, 4]");
}

#[test]
fn test_send_with_non_constant_keyword_default() {
    assert_snapshot!(inspect("
        def dbl(x = 1) = x * 2

        def foo(a: dbl, b: dbl(2), c: dbl(2 ** 3))
          [a, b, c]
        end

        def test
          [
            foo,
            foo(a: 10),
            foo(b: 20),
            foo(c: 30),
            foo(a: 10, b: 20, c: 30)
          ]
        end

        test
        test
    "), @"[[2, 4, 16], [10, 4, 16], [2, 20, 16], [2, 4, 30], [10, 20, 30]]");
}

#[test]
fn test_send_with_non_constant_keyword_default_not_evaluated_when_provided() {
    assert_snapshot!(inspect("
        def foo(a: raise, b: raise, c: raise)
          [a, b, c]
        end

        def test
          foo(a: 1, b: 2, c: 3)
        end

        test
        test
    "), @"[1, 2, 3]");
}

#[test]
fn test_send_with_non_constant_keyword_default_evaluated_when_not_provided() {
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

#[test]
fn test_send_with_non_constant_keyword_default_jit_to_jit() {
    assert_snapshot!(inspect("
        def make_default(x) = x * 2

        def callee(a: make_default(1), b: make_default(2), c: make_default(3))
          [a, b, c]
        end

        def caller_method
          callee
        end

        # Warm up callee first so it gets JITted
        callee
        callee

        # Now warm up caller - this creates JIT-to-JIT call
        caller_method
        caller_method
    "), @"[2, 4, 6]");
}

#[test]
fn test_send_with_non_constant_keyword_default_side_exit() {
    assert_snapshot!(inspect("
        def make_b = 2

        def callee(a: 1, b: make_b, c: 3)
          x = binding.local_variable_get(:a)
          y = binding.local_variable_get(:b)
          z = binding.local_variable_get(:c)
          [x, y, z]
        end

        def test
          callee(a: 10, c: 30)
        end

        test
        test
    "), @"[10, 2, 30]");
}

#[test]
fn test_send_with_non_constant_keyword_default_evaluation_order() {
    assert_snapshot!(inspect(r#"
        def log(x)
          $order << x
          x
        end

        def foo(a: log("a"), b: log("b"), c: log("c"))
          [a, b, c]
        end

        def test
          results = []

          $order = []
          foo
          results << $order.dup

          $order = []
          foo(a: "A")
          results << $order.dup

          $order = []
          foo(b: "B")
          results << $order.dup

          $order = []
          foo(c: "C")
          results << $order.dup

          results
        end

        test
        test
    "#), @r#"[["a", "b", "c"], ["b", "c"], ["a", "c"], ["a", "b"]]"#);
}

#[test]
fn test_send_with_too_many_non_constant_keyword_defaults() {
    assert_snapshot!(inspect("
        def many_kwargs( k1: 1, k2: 2, k3: 3, k4: 4, k5: 5, k6: 6, k7: 7, k8: 8, k9: 9, k10: 10, k11: 11, k12: 12, k13: 13, k14: 14, k15: 15, k16: 16, k17: 17, k18: 18, k19: 19, k20: 20, k21: 21, k22: 22, k23: 23, k24: 24, k25: 25, k26: 26, k27: 27, k28: 28, k29: 29, k30: 30, k31: 31, k32: 32, k33: 33, k34: k33 + 1) = k1 + k34
        def t = many_kwargs
        t
        t
    "), @"35");
}

#[test]
fn test_invokebuiltin_delegate() {
    assert_snapshot!(inspect("
        def test = [].clone(freeze: true)
        r = test
        r2 = test
        [r2, r2.frozen?]
    "), @"[[], true]");
}

#[test]
fn test_opt_plus_const() {
    assert_snapshot!(inspect("
        def test = 1 + 2
        test # profile opt_plus
        test
    "), @"3");
}

#[test]
fn test_opt_plus_fixnum() {
    assert_snapshot!(inspect("
        def test(a, b) = a + b
        test(0, 1) # profile opt_plus
        test(1, 2)
    "), @"3");
}

#[test]
fn test_opt_plus_chain() {
    assert_snapshot!(inspect("
        def test(a, b, c) = a + b + c
        test(0, 1, 2) # profile opt_plus
        test(1, 2, 3)
    "), @"6");
}

#[test]
fn test_opt_plus_left_imm() {
    assert_snapshot!(inspect("
        def test(a) = 1 + a
        test(1) # profile opt_plus
        test(2)
    "), @"3");
}

#[test]
fn test_opt_plus_type_guard_exit() {
    assert_snapshot!(inspect("
        def test(a) = 1 + a
        test(1) # profile opt_plus
        [test(2), test(2.0)]
    "), @"[3, 3.0]");
}

#[test]
fn test_opt_plus_type_guard_exit_with_locals() {
    assert_snapshot!(inspect("
        def test(a)
          local = 3
          1 + a + local
        end
        test(1) # profile opt_plus
        [test(2), test(2.0)]
    "), @"[6, 6.0]");
}

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

#[test]
fn test_opt_plus_type_guard_nested_exit_with_locals() {
    assert_snapshot!(inspect("
        def side_exit(n)
          local = 2
          1 + n + local
        end
        def jit_frame(n)
          local = 3
          1 + side_exit(n) + local
        end
        def entry(n) = jit_frame(n)
        entry(2) # profile send
        [entry(2), entry(2.0)]
    "), @"[9, 9.0]");
}

#[test]
fn test_opt_minus() {
    assert_snapshot!(inspect("
        def test(a, b) = a - b
        test(2, 1) # profile opt_minus
        test(6, 4)
    "), @"2");
}

#[test]
fn test_opt_mult() {
    assert_snapshot!(inspect("
        def test(a, b) = a * b
        test(1, 2) # profile opt_mult
        test(2, 3)
    "), @"6");
}

#[test]
fn test_opt_mult_overflow() {
    assert_snapshot!(inspect("
        def test(a, b)
          a * b
        end
        test(1, 1) # profile opt_mult

        r1 = test(2, 3)
        r2 = test(2, -3)
        r3 = test(2 << 40, 2 << 41)
        r4 = test(2 << 40, -2 << 41)
        r5 = test(1 << 62, 1 << 62)

        [r1, r2, r3, r4, r5]
    "), @"[6, -6, 9671406556917033397649408, -9671406556917033397649408, 21267647932558653966460912964485513216]");
}

#[test]
fn test_opt_eq() {
    eval("
        def test(a, b) = a == b
        test(0, 2) # profile opt_eq
    ");
    assert_contains_opcode("test", YARVINSN_opt_eq);
    assert_snapshot!(inspect("[test(1, 1), test(0, 1)]"), @"[true, false]");
}

#[test]
fn test_opt_eq_with_minus_one() {
    eval("
        def test(a) = a == -1
        test(1) # profile opt_eq
    ");
    assert_contains_opcode("test", YARVINSN_opt_eq);
    assert_snapshot!(inspect("[test(0), test(-1)]"), @"[false, true]");
}

#[test]
fn test_opt_neq_dynamic() {
    eval("
        def test(a, b) = a != b
        test(0, 2) # profile opt_neq
    ");
    assert_contains_opcode("test", YARVINSN_opt_neq);
    assert_snapshot!(inspect("[test(1, 1), test(0, 1)]"), @"[false, true]");
}

#[test]
fn test_opt_neq_fixnum() {
    assert_snapshot!(inspect("
        def test(a, b) = a != b
        test(0, 2) # profile opt_neq
        [test(1, 1), test(0, 1)]
    "), @"[false, true]");
}

#[test]
fn test_opt_lt() {
    eval("
        def test(a, b) = a < b
        test(2, 3) # profile opt_lt
    ");
    assert_contains_opcode("test", YARVINSN_opt_lt);
    assert_snapshot!(inspect("[test(0, 1), test(0, 0), test(1, 0)]"), @"[true, false, false]");
}

#[test]
fn test_opt_lt_with_literal_lhs() {
    eval("
        def test(n) = 2 < n
        test(2) # profile opt_lt
    ");
    assert_contains_opcode("test", YARVINSN_opt_lt);
    assert_snapshot!(inspect("[test(1), test(2), test(3)]"), @"[false, false, true]");
}

#[test]
fn test_opt_le() {
    eval("
        def test(a, b) = a <= b
        test(2, 3) # profile opt_le
    ");
    assert_contains_opcode("test", YARVINSN_opt_le);
    assert_snapshot!(inspect("[test(0, 1), test(0, 0), test(1, 0)]"), @"[true, true, false]");
}

#[test]
fn test_opt_gt() {
    eval("
        def test(a, b) = a > b
        test(2, 3) # profile opt_gt
    ");
    assert_contains_opcode("test", YARVINSN_opt_gt);
    assert_snapshot!(inspect("[test(0, 1), test(0, 0), test(1, 0)]"), @"[false, false, true]");
}

#[test]
fn test_opt_empty_p() {
    eval("
        def test(x) = x.empty?
    ");
    assert_contains_opcode("test", YARVINSN_opt_empty_p);
    assert_snapshot!(inspect("[test([1]), test(\"1\"), test({})]"), @"[false, false, true]");
}

#[test]
fn test_opt_succ() {
    eval("
        def test(obj) = obj.succ
    ");
    assert_contains_opcode("test", YARVINSN_opt_succ);
    assert_snapshot!(inspect(r#"[test(-1), test("A")]"#), @r#"[0, "B"]"#);
}

#[test]
fn test_opt_and() {
    eval("
        def test(x, y) = x & y
    ");
    assert_contains_opcode("test", YARVINSN_opt_and);
    assert_snapshot!(inspect("[test(0b1101, 3), test([3, 2, 1, 4], [8, 1, 2, 3])]"), @"[1, [3, 2, 1]]");
}

#[test]
fn test_opt_or() {
    eval("
        def test(x, y) = x | y
    ");
    assert_contains_opcode("test", YARVINSN_opt_or);
    assert_snapshot!(inspect("[test(0b1000, 3), test([3, 2, 1], [1, 2, 3])]"), @"[11, [3, 2, 1]]");
}

#[test]
fn test_fixnum_and() {
    eval("
        def test(a, b) = a & b
    ");
    assert_contains_opcode("test", YARVINSN_opt_and);
    assert_snapshot!(inspect("
        [
                  test(5, 3),
                  test(0b011, 0b110),
                  test(-0b011, 0b110)
                ]
    "), @"[1, 2, 4]");
}

#[test]
fn test_fixnum_and_side_exit() {
    eval("
        def test(a, b) = a & b
    ");
    assert_contains_opcode("test", YARVINSN_opt_and);
    assert_snapshot!(inspect("
        [
                  test(2, 2),
                  test(0b011, 0b110),
                  test(true, false)
                ]
    "), @"[2, 2, false]");
}

#[test]
fn test_fixnum_or() {
    eval("
        def test(a, b) = a | b
    ");
    assert_contains_opcode("test", YARVINSN_opt_or);
    assert_snapshot!(inspect("
        [
                  test(5, 3),
                  test(1, 2),
                  test(1, -4)
                ]
    "), @"[7, 3, -3]");
}

#[test]
fn test_fixnum_or_side_exit() {
    eval("
        def test(a, b) = a | b
    ");
    assert_contains_opcode("test", YARVINSN_opt_or);
    assert_snapshot!(inspect("
        [
                  test(1, 2),
                  test(2, 2),
                  test(true, false)
                ]
    "), @"[3, 2, true]");
}

#[test]
fn test_fixnum_xor() {
    assert_snapshot!(inspect("
        def test(a, b) = a ^ b
        [
          test(5, 3),
          test(-5, 3),
          test(1, 2)
        ]
    "), @"[6, -8, 3]");
}

#[test]
fn test_fixnum_xor_side_exit() {
    assert_snapshot!(inspect("
        def test(a, b) = a ^ b
        [
          test(5, 3),
          test(5, 3),
          test(true, false)
        ]
    "), @"[6, 6, true]");
}

#[test]
fn test_fixnum_mul() {
    eval("
        C = 3
        def test(n) = C * n
        test(4)
        test(4)
    ");
    assert_contains_opcode("test", YARVINSN_opt_mult);
    assert_snapshot!(inspect("test(4)"), @"12");
}

#[test]
fn test_fixnum_div() {
    eval("
        C = 48
        def test(n) = C / n
        test(4)
    ");
    assert_contains_opcode("test", YARVINSN_opt_div);
    assert_snapshot!(inspect("test(4)"), @"12");
}

#[test]
fn test_fixnum_floor() {
    eval("
        C = 3
        def test(n) = C / n
        test(4)
    ");
    assert_contains_opcode("test", YARVINSN_opt_div);
    assert_snapshot!(inspect("test(4)"), @"0");
}

#[test]
fn test_opt_not() {
    eval("
        def test(obj) = !obj
    ");
    assert_contains_opcode("test", YARVINSN_opt_not);
    assert_snapshot!(inspect("[test(nil), test(false), test(0)]"), @"[true, true, false]");
}

#[test]
fn test_opt_regexpmatch2() {
    eval("
        def test(haystack) = /needle/ =~ haystack
    ");
    assert_contains_opcode("test", YARVINSN_opt_regexpmatch2);
    assert_snapshot!(inspect(r#"[test("kneedle"), test("")]"#), @"[1, nil]");
}

#[test]
fn test_opt_ge() {
    eval("
        def test(a, b) = a >= b
        test(2, 3) # profile opt_ge
    ");
    assert_contains_opcode("test", YARVINSN_opt_ge);
    assert_snapshot!(inspect("[test(0, 1), test(0, 0), test(1, 0)]"), @"[false, true, true]");
}

#[test]
fn test_opt_new_does_not_push_frame() {
    eval("
        class Foo
          attr_reader :backtrace
          def initialize
            @backtrace = caller
          end
        end
        def test = Foo.new
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_new);
    assert_snapshot!(inspect("
        foo = test
        foo.backtrace.find { |frame| frame.include?('Class#new') }
    "), @"nil");
}

#[test]
fn test_opt_new_with_redefined() {
    eval(r#"
        class Foo
          def self.new = "foo"
          def initialize = raise("unreachable")
        end
        def test = Foo.new
        test
    "#);
    assert_contains_opcode("test", YARVINSN_opt_new);
    assert_snapshot!(inspect(r#"test"#), @r#""foo""#);
}

#[test]
fn test_opt_new_invalidate_new() {
    eval(r#"
        class Foo; end
        def test = Foo.new
        test
    "#);
    assert_contains_opcode("test", YARVINSN_opt_new);
    assert_snapshot!(inspect(r#"
        result = [test.class.name]
        def Foo.new = "foo"
        result << test
    "#), @r#"["Foo", "foo"]"#);
}

#[test]
fn test_opt_newarray_send_include_p() {
    eval("
        def test(x)
            [:y, 1, Object.new].include?(x)
        end
        test(1)
    ");
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect("[test(1), test(\"n\")]"), @"[true, false]");
}

#[test]
fn test_opt_newarray_send_include_p_redefined() {
    eval("
        class Array
            alias_method :old_include?, :include?
            def include?(x)
                old_include?(x) ? :true : :false
            end
        end
        def test(x)
            [:y, 1, Object.new].include?(x)
        end
    ");
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect("
        def test(x)
            [:y, 1, Object.new].include?(x)
        end
        test(1)
        [test(1), test(\"n\")]
    "), @"[:true, :false]");
}

#[test]
fn test_opt_duparray_send_include_p() {
    eval("
        def test(x)
            [:y, 1].include?(x)
        end
        test(1)
    ");
    assert_contains_opcode("test", YARVINSN_opt_duparray_send);
    assert_snapshot!(inspect("[test(1), test(\"n\")]"), @"[true, false]");
}

#[test]
fn test_opt_duparray_send_include_p_redefined() {
    eval("
        class Array
            alias_method :old_include?, :include?
            def include?(x)
                old_include?(x) ? :true : :false
            end
        end
        def test(x)
            [:y, 1].include?(x)
        end
    ");
    assert_contains_opcode("test", YARVINSN_opt_duparray_send);
    assert_snapshot!(inspect("
        def test(x)
            [:y, 1].include?(x)
        end
        test(1)
        [test(1), test(\"n\")]
    "), @"[:true, :false]");
}

#[test]
fn test_opt_newarray_send_pack_buffer() {
    eval(r#"
        def test(num, buffer)
            [num].pack('C', buffer:)
        end
        test(65, "")
    "#);
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect(r#"
        buf = ""
        [test(65, buf), test(66, buf), test(67, buf), buf]
    "#), @r#"["ABC", "ABC", "ABC", "ABC"]"#);
}

#[test]
fn test_opt_newarray_send_pack_buffer_redefined() {
    eval(r#"
        class Array
            alias_method :old_pack, :pack
            def pack(fmt, buffer: nil)
                old_pack(fmt, buffer: buffer)
                "b"
            end
        end
        def test(num, buffer)
            [num].pack('C', buffer:)
        end
    "#);
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect(r#"
        def test(num, buffer)
            [num].pack('C', buffer:)
        end
        buf = ""
        test(65, buf)
        buf = ""
        [test(65, buf), buf]
    "#), @r#"["b", "A"]"#);
}

#[test]
fn test_opt_newarray_send_hash() {
    eval("
        def test(x)
            [1, 2, x].hash
        end
        test(20)
    ");
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect("test(20).class"), @"Integer");
}

#[test]
fn test_opt_newarray_send_hash_redefined() {
    eval("
        Array.class_eval { def hash = 42 }
        def test(x)
            [1, 2, x].hash
        end
        test(20)
    ");
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect("test(20)"), @"42");
}

#[test]
fn test_opt_newarray_send_max() {
    eval("
        def test(a,b) = [a,b].max
        test(10, 20)
    ");
    assert_contains_opcode("test", YARVINSN_opt_newarray_send);
    assert_snapshot!(inspect("[test(10, 20), test(40, 30)]"), @"[20, 40]");
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
    assert_snapshot!(inspect("
        def test(a,b) = [a,b].max
        test(15, 30)
        [test(15, 30), test(45, 35)]
    "), @"[60, 90]");
}

#[test]
fn test_new_hash_empty() {
    eval("
        def test = {}
        test
    ");
    assert_contains_opcode("test", YARVINSN_newhash);
    assert_snapshot!(inspect("test"), @"{}");
}

#[test]
fn test_new_hash_nonempty() {
    eval(r#"
        def test
            key = "key"
            value = "value"
            num = 42
            result = 100
            {key => value, num => result}
        end
        test
    "#);
    assert_contains_opcode("test", YARVINSN_newhash);
    assert_snapshot!(inspect(r#"test"#), @r#"{"key" => "value", 42 => 100}"#);
}

#[test]
fn test_new_hash_single_key_value() {
    eval(r#"
        def test = {"key" => "value"}
        test
    "#);
    assert_contains_opcode("test", YARVINSN_newhash);
    assert_snapshot!(inspect(r#"test"#), @r#"{"key" => "value"}"#);
}

#[test]
fn test_new_hash_with_computation() {
    eval(r#"
        def test(a, b)
            {"sum" => a + b, "product" => a * b}
        end
        test(2, 3)
    "#);
    assert_contains_opcode("test", YARVINSN_newhash);
    assert_snapshot!(inspect(r#"test(2, 3)"#), @r#"{"sum" => 5, "product" => 6}"#);
}

#[test]
fn test_new_hash_with_user_defined_hash_method() {
    assert_snapshot!(inspect(r#"
        class CustomKey
            attr_reader :val
            def initialize(val)
                @val = val
            end
            def hash
                @val.hash
            end
            def eql?(other)
                other.is_a?(CustomKey) && @val == other.val
            end
        end
        def test
            key = CustomKey.new("key")
            hash = {key => "value"}
            hash[key] == "value"
        end
        test
        test
    "#), @"true");
}

#[test]
fn test_new_hash_with_user_hash_method_exception() {
    assert_snapshot!(inspect(r#"
        class BadKey
            def hash
                raise "Hash method failed!"
            end
        end
        def test
            key = BadKey.new
            {key => "value"}
        end
        begin
            test
        rescue => e
            e.class
        end
        begin
            test
        rescue => e
            e.class
        end
    "#), @"RuntimeError");
}

#[test]
fn test_new_hash_with_user_eql_method_exception() {
    assert_snapshot!(inspect(r#"
        class BadKey
            def hash
                42
            end
            def eql?(other)
                raise "Eql method failed!"
            end
        end
        def test
            key1 = BadKey.new
            key2 = BadKey.new
            {key1 => "value1", key2 => "value2"}
        end
        begin
            test
        rescue => e
            e.class
        end
        begin
            test
        rescue => e
            e.class
        end
    "#), @"RuntimeError");
}

#[test]
fn test_opt_hash_freeze() {
    eval("
        def test = {}.freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_hash_freeze);
    assert_snapshot!(inspect("
        result = [test]
        class Hash
          def freeze = 5
        end
        result << test
    "), @"[{}, 5]");
}

#[test]
fn test_opt_hash_freeze_rewritten() {
    eval("
        class Hash
            def freeze = 5
        end
        def test = {}.freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_hash_freeze);
    assert_snapshot!(inspect("test"), @"5");
}

#[test]
fn test_opt_aset_hash() {
    eval("
        def test(h, k, v)
            h[k] = v
        end
        test({}, :key, 42)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aset);
    assert_snapshot!(inspect("h = {}; test(h, :key, 42); h[:key]"), @"42");
}

#[test]
fn test_opt_aset_hash_returns_value() {
    assert_snapshot!(inspect("
        def test(h, k, v)
            h[k] = v
        end
        test({}, :key, 100)
        test({}, :key, 100)
    "), @"100");
}

#[test]
fn test_opt_aset_hash_string_key() {
    assert_snapshot!(inspect(r#"
        def test(h, k, v)
            h[k] = v
        end
        h = {}
        test(h, "foo", "bar")
        test(h, "foo", "bar")
        h["foo"]
    "#), @r#""bar""#);
}

#[test]
fn test_opt_aset_hash_subclass() {
    assert_snapshot!(inspect("
        class MyHash < Hash; end
        def test(h, k, v)
            h[k] = v
        end
        h = MyHash.new
        test(h, :key, 42)
        test(h, :key, 42)
        h[:key]
    "), @"42");
}

#[test]
fn test_opt_aset_hash_too_few_args() {
    assert_snapshot!(inspect(r#"
        def test(h)
            h.[]= 123
        rescue ArgumentError
            "ArgumentError"
        end
        test({})
        test({})
    "#), @r#""ArgumentError""#);
}

#[test]
fn test_opt_aset_hash_too_many_args() {
    assert_snapshot!(inspect(r#"
        def test(h)
            h[:a, :b] = :c
        rescue ArgumentError
            "ArgumentError"
        end
        test({})
        test({})
    "#), @r#""ArgumentError""#);
}

#[test]
fn test_opt_ary_freeze() {
    eval("
        def test = [].freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_ary_freeze);
    assert_snapshot!(inspect("
        result = [test]
        class Array
          def freeze = 5
        end
        result << test
    "), @"[[], 5]");
}

#[test]
fn test_opt_ary_freeze_rewritten() {
    eval("
        class Array
            def freeze = 5
        end
        def test = [].freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_ary_freeze);
    assert_snapshot!(inspect("test"), @"5");
}

#[test]
fn test_opt_str_freeze() {
    eval("
        def test = ''.freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_str_freeze);
    assert_snapshot!(inspect(r#"
        result = [test]
        class String
          def freeze = 5
        end
        result << test
    "#), @r#"["", 5]"#);
}

#[test]
fn test_opt_str_freeze_rewritten() {
    eval("
        class String
            def freeze = 5
        end
        def test = ''.freeze
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_str_freeze);
    assert_snapshot!(inspect("test"), @"5");
}

#[test]
fn test_opt_str_uminus() {
    eval("
        def test = -''
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_str_uminus);
    assert_snapshot!(inspect(r#"
        result = [test]
        class String
          def -@ = 5
        end
        result << test
    "#), @r#"["", 5]"#);
}

#[test]
fn test_opt_str_uminus_rewritten() {
    eval("
        class String
            def -@ = 5
        end
        def test = -''
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_str_uminus);
    assert_snapshot!(inspect("test"), @"5");
}

#[test]
fn test_new_array_empty() {
    eval("
        def test = []
        test
    ");
    assert_contains_opcode("test", YARVINSN_newarray);
    assert_snapshot!(inspect("test"), @"[]");
}

#[test]
fn test_new_array_nonempty() {
    assert_snapshot!(inspect("
        def a = 5
        def test = [a]
        test
        test
    "), @"[5]");
}

#[test]
fn test_new_array_order() {
    assert_snapshot!(inspect("
        def a = 3
        def b = 2
        def c = 1
        def test = [a, b, c]
        test
        test
    "), @"[3, 2, 1]");
}

#[test]
fn test_array_dup() {
    assert_snapshot!(inspect("
        def test = [1,2,3]
        test
        test
    "), @"[1, 2, 3]");
}

#[test]
fn test_array_fixnum_aref() {
    eval("
        def test(x) = [1,2,3][x]
        test(2)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(2)"), @"3");
}

#[test]
fn test_array_fixnum_aref_negative_index() {
    eval("
        def test(x) = [1,2,3][x]
        test(-1)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(-1)"), @"3");
}

#[test]
fn test_array_fixnum_aref_out_of_bounds_positive() {
    eval("
        def test(x) = [1,2,3][x]
        test(10)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(10)"), @"nil");
}

#[test]
fn test_array_fixnum_aref_out_of_bounds_negative() {
    eval("
        def test(x) = [1,2,3][x]
        test(-10)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(-10)"), @"nil");
}

#[test]
fn test_array_fixnum_aref_array_subclass() {
    eval("
        class MyArray < Array; end
        def test(arr, idx) = arr[idx]
        test(MyArray[1,2,3], 2)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aref);
    assert_snapshot!(inspect("test(MyArray[1,2,3], 2)"), @"3");
}

#[test]
fn test_array_aref_non_fixnum_index() {
    assert_snapshot!(inspect(r#"
        def test(arr, idx) = arr[idx]
        test([1,2,3], 1)
        test([1,2,3], 1)
        begin
            test([1,2,3], "1")
        rescue => e
            e.class
        end
    "#), @"TypeError");
}

#[test]
fn test_array_fixnum_aset() {
    eval("
        def test(arr, idx)
            arr[idx] = 7
        end
        test([1,2,3], 2)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aset);
    assert_snapshot!(inspect("arr = [1,2,3]; test(arr, 2); arr"), @"[1, 2, 7]");
}

#[test]
fn test_array_fixnum_aset_returns_value() {
    eval("
        def test(arr, idx)
            arr[idx] = 7
        end
        test([1,2,3], 2)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aset);
    assert_snapshot!(inspect("test([1,2,3], 2)"), @"7");
}

#[test]
fn test_array_fixnum_aset_out_of_bounds() {
    assert_snapshot!(inspect("
        def test(arr)
            arr[5] = 7
        end
        arr = [1,2,3]
        test(arr)
        arr = [1,2,3]
        test(arr)
        arr
    "), @"[1, 2, 3, nil, nil, 7]");
}

#[test]
fn test_array_fixnum_aset_negative_index() {
    assert_snapshot!(inspect("
        def test(arr)
            arr[-1] = 7
        end
        arr = [1,2,3]
        test(arr)
        arr = [1,2,3]
        test(arr)
        arr
    "), @"[1, 2, 7]");
}

#[test]
fn test_array_fixnum_aset_shared() {
    assert_snapshot!(inspect("
        def test(arr, idx, val)
            arr[idx] = val
        end
        arr = (0..50).to_a
        test(arr, 0, -1)
        test(arr, 1, -2)
        shared = arr[10, 20]
        test(shared, 0, 999)
        [arr[10], shared[0], arr[0], arr[1]]
    "), @"[10, 999, -1, -2]");
}

#[test]
fn test_array_fixnum_aset_frozen() {
    assert_snapshot!(inspect("
        def test(arr, idx, val)
            arr[idx] = val
        end
        arr = [1,2,3]
        test(arr, 1, 9)
        test(arr, 1, 9)
        arr.freeze
        begin
            test(arr, 1, 9)
        rescue => e
            e.class
        end
    "), @"FrozenError");
}

#[test]
fn test_array_fixnum_aset_array_subclass() {
    eval("
        class MyArray < Array; end
        def test(arr, idx)
            arr[idx] = 7
        end
        test(MyArray.new, 0)
    ");
    assert_contains_opcode("test", YARVINSN_opt_aset);
    assert_snapshot!(inspect("arr = MyArray.new; test(arr, 0); arr[0]"), @"7");
}

#[test]
fn test_array_aset_non_fixnum_index() {
    assert_snapshot!(inspect(r#"
        def test(arr, idx)
            arr[idx] = 7
        end
        test([1,2,3], 0)
        test([1,2,3], 0)
        begin
            test([1,2,3], "0")
        rescue => e
            e.class
        end
    "#), @"TypeError");
}

#[test]
fn test_empty_array_pop() {
    assert_snapshot!(inspect("
        def test(arr) = arr.pop
        test([])
        test([])
    "), @"nil");
}

#[test]
fn test_array_pop_no_arg() {
    assert_snapshot!(inspect("
        def test(arr) = arr.pop
        test([32, 33, 42])
        test([32, 33, 42])
    "), @"42");
}

#[test]
fn test_array_pop_arg() {
    assert_snapshot!(inspect("
        def test(arr) = arr.pop(2)
        test([32, 33, 42])
        test([32, 33, 42])
    "), @"[33, 42]");
}

#[test]
fn test_new_range_inclusive() {
    assert_snapshot!(inspect("
        def test(a, b) = a..b
        test(1, 5)
        test(1, 5)
    "), @"1..5");
}

#[test]
fn test_new_range_exclusive() {
    assert_snapshot!(inspect("
        def test(a, b) = a...b
        test(1, 5)
        test(1, 5)
    "), @"1...5");
}

#[test]
fn test_new_range_with_literal() {
    assert_snapshot!(inspect("
        def test(n) = n..10
        test(3)
        test(3)
    "), @"3..10");
}

#[test]
fn test_new_range_fixnum_both_literals_inclusive() {
    eval("
        def test()
          a = 2
          (1..a)
        end
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test; test"), @"1..2");
}

#[test]
fn test_new_range_fixnum_both_literals_exclusive() {
    eval("
        def test()
          a = 2
          (1...a)
        end
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test; test"), @"1...2");
}

#[test]
fn test_new_range_fixnum_low_literal_inclusive() {
    eval("
        def test(a) = (1..a)
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test(2); test(3)"), @"1..3");
}

#[test]
fn test_new_range_fixnum_low_literal_exclusive() {
    eval("
        def test(a) = (1...a)
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test(2); test(3)"), @"1...3");
}

#[test]
fn test_new_range_fixnum_high_literal_inclusive() {
    eval("
        def test(a) = (a..10)
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test(2); test(3)"), @"3..10");
}

#[test]
fn test_new_range_fixnum_high_literal_exclusive() {
    eval("
        def test(a) = (a...10)
    ");
    assert_contains_opcode("test", YARVINSN_newrange);
    assert_snapshot!(inspect("test(2); test(3)"), @"3...10");
}

#[test]
fn test_if() {
    assert_snapshot!(inspect("
        def test(n)
          if n < 5
            0
          end
        end
        test(3)
        [test(3), test(7)]
    "), @"[0, nil]");
}

#[test]
fn test_if_else() {
    assert_snapshot!(inspect("
        def test(n)
          if n < 5
            0
          else
            1
          end
        end
        test(3)
        [test(3), test(7)]
    "), @"[0, 1]");
}

#[test]
fn test_if_else_params() {
    assert_snapshot!(inspect("
        def test(n, a, b)
          if n < 5
            a
          else
            b
          end
        end
        test(3, 1, 2)
        [test(3, 1, 2), test(7, 10, 20)]
    "), @"[1, 20]");
}

#[test]
fn test_if_else_nested() {
    assert_snapshot!(inspect("
        def test(a, b, c, d, e)
          if 2 < a
            if a < 4
              b
            else
              c
            end
          else
            if a < 0
              d
            else
              e
            end
          end
        end
        test(-1, 1, 2, 3, 4)
        [
          test(-1,  1,  2,  3,  4),
          test( 0,  5,  6,  7,  8),
          test( 3,  9, 10, 11, 12),
          test( 5, 13, 14, 15, 16),
        ]
    "), @"[3, 8, 9, 14]");
}

#[test]
fn test_if_else_chained() {
    assert_snapshot!(inspect("
        def test(a)
          (if 2 < a then 1 else 2 end) + (if a < 4 then 10 else 20 end)
        end
        test(0)
        [test(0), test(3), test(5)]
    "), @"[12, 11, 21]");
}

#[test]
fn test_if_elsif_else() {
    assert_snapshot!(inspect("
        def test(n)
          if n < 5
            0
          elsif 8 < n
            1
          else
            2
          end
        end
        test(3)
        [test(3), test(7), test(9)]
    "), @"[0, 2, 1]");
}

#[test]
fn test_ternary_operator() {
    assert_snapshot!(inspect("
        def test(n, a, b)
          n < 5 ? a : b
        end
        test(3, 1, 2)
        [test(3, 1, 2), test(7, 10, 20)]
    "), @"[1, 20]");
}

#[test]
fn test_ternary_operator_nested() {
    assert_snapshot!(inspect("
        def test(n, a, b)
          (n < 5 ? a : b) + 1
        end
        test(3, 1, 2)
        [test(3, 1, 2), test(7, 10, 20)]
    "), @"[2, 21]");
}

#[test]
fn test_while_loop() {
    assert_snapshot!(inspect("
        def test(n)
          i = 0
          while i < n
            i = i + 1
          end
          i
        end
        test(10)
        test(10)
    "), @"10");
}

#[test]
fn test_while_loop_chain() {
    assert_snapshot!(inspect("
        def test(n)
          i = 0
          while i < n
            i = i + 1
          end
          while i < n * 10
            i = i * 3
          end
          i
        end
        test(5)
        [test(5), test(10)]
    "), @"[135, 270]");
}

#[test]
fn test_while_loop_nested() {
    assert_snapshot!(inspect("
        def test(n, m)
          i = 0
          while i < n
            j = 0
            while j < m
              j += 2
            end
            i += j
          end
          i
        end
        test(0, 0)
        [test(0, 0), test(1, 3), test(10, 5)]
    "), @"[0, 4, 12]");
}

#[test]
fn test_while_loop_if_else() {
    assert_snapshot!(inspect("
        def test(n)
          i = 0
          while i < n
            if n >= 10
              return -1
            else
              i = i + 1
            end
          end
          i
        end
        test(9)
        [test(9), test(10)]
    "), @"[9, -1]");
}

#[test]
fn test_if_while_loop() {
    assert_snapshot!(inspect("
        def test(n)
          i = 0
          if n < 10
            while i < n
              i += 1
            end
          else
            while i < n
              i += 3
            end
          end
          i
        end
        test(9)
        [test(9), test(10)]
    "), @"[9, 12]");
}

#[test]
fn test_live_reg_past_ccall() {
    assert_snapshot!(inspect("
        def callee = 1
        def test = callee + callee
        test
        test
    "), @"2");
}

#[test]
fn test_method_call() {
    assert_snapshot!(inspect("
        def callee(a, b)
          a - b
        end
        def test
          callee(4, 2) + 10
        end
        test
        test
    "), @"12");
}

#[test]
fn test_recursive_fact() {
    assert_snapshot!(inspect("
        def fact(n)
          if n == 0
            return 1
          end
          return n * fact(n-1)
        end
        fact(0)
        [fact(0), fact(3), fact(6)]
    "), @"[1, 6, 720]");
}

#[test]
fn test_recursive_fib() {
    assert_snapshot!(inspect("
        def fib(n)
          if n < 2
            return n
          end
          return fib(n-1) + fib(n-2)
        end
        fib(0)
        [fib(0), fib(3), fib(4)]
    "), @"[0, 2, 3]");
}

#[test]
fn test_spilled_basic_block_args() {
    assert_snapshot!(inspect("
        def test(n1, n2)
          n3 = 3
          n4 = 4
          n5 = 5
          n6 = 6
          n7 = 7
          n8 = 8
          n9 = 9
          n10 = 10
          if n1 < n2
            n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + n10
          end
        end
        test(1, 2)
        test(1, 2)
    "), @"55");
}

#[test]
fn test_putself() {
    assert_snapshot!(inspect("
        class Integer
          def minus(a)
            self - a
          end
        end
        5.minus(2)
        5.minus(2)
    "), @"3");
}

#[test]
fn test_getinstancevariable_nil() {
    assert_snapshot!(inspect("
        def test() = @foo
        test()
        test()
    "), @"nil");
}

#[test]
fn test_getinstancevariable() {
    assert_snapshot!(inspect("
        @foo = 3
        def test() = @foo
        test()
        test()
    "), @"3");
}

#[test]
fn test_getinstancevariable_miss() {
    assert_snapshot!(inspect("
        class C
          def foo
            @foo
          end
          def foo_then_bar
            @foo = 1
            @bar = 2
          end
          def bar_then_foo
            @bar = 3
            @foo = 4
          end
        end
        o1 = C.new
        o1.foo_then_bar
        result = []
        result << o1.foo
        result << o1.foo
        o2 = C.new
        o2.bar_then_foo
        result << o2.foo
        result
    "), @"[1, 1, 4]");
}

#[test]
fn test_setinstancevariable() {
    assert_snapshot!(inspect("
        def test() = @foo = 1
        test()
        test()
        @foo
    "), @"1");
}

#[test]
fn test_getclassvariable() {
    assert_snapshot!(inspect("
        class Foo
          def self.test = @@x
        end
        Foo.class_variable_set(:@@x, 42)
        Foo.test()
        Foo.test()
    "), @"42");
}

#[test]
fn test_getclassvariable_raises() {
    assert_snapshot!(inspect(r#"
        class Foo
          def self.test = @@x
        end
        begin
          Foo.test
          Foo.test
        rescue NameError => e
          e.message
        end
    "#), @r#""uninitialized class variable @@x in Foo""#);
}

#[test]
fn test_setclassvariable() {
    assert_snapshot!(inspect("
        class Foo
          def self.test = @@x = 42
        end
        Foo.test()
        Foo.test()
        Foo.class_variable_get(:@@x)
    "), @"42");
}

#[test]
fn test_setclassvariable_raises() {
    assert_snapshot!(inspect(r#"
        class Foo
          def self.test = @@x = 42
          freeze
        end
        begin
          Foo.test
          Foo.test
        rescue FrozenError => e
          e.message
        end
    "#), @r#""can't modify frozen Class: Foo""#);
}

#[test]
fn test_attr_reader() {
    eval("
        class C
          attr_reader :foo
          def initialize
            @foo = 4
          end
        end
        def test(c) = c.foo
        test(C.new)
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("c = C.new; [test(c), test(c)]"), @"[4, 4]");
}

#[test]
fn test_attr_accessor_getivar() {
    eval("
        class C
          attr_accessor :foo
          def initialize
            @foo = 4
          end
        end
        def test(c) = c.foo
        test(C.new)
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("c = C.new; [test(c), test(c)]"), @"[4, 4]");
}

#[test]
fn test_attr_accessor_setivar() {
    eval("
        class C
          attr_accessor :foo
          def initialize
            @foo = 4
          end
        end
        def test(c)
          c.foo = 5
          c.foo
        end
        test(C.new)
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("c = C.new; [test(c), test(c)]"), @"[5, 5]");
}

#[test]
fn test_attr_writer() {
    eval("
        class C
          attr_writer :foo
          def initialize
            @foo = 4
          end
          def get_foo = @foo
        end
        def test(c)
          c.foo = 5
          c.get_foo
        end
        test(C.new)
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("c = C.new; [test(c), test(c)]"), @"[5, 5]");
}

#[test]
fn test_getconstant() {
    eval("
        class Foo
          CONST = 1
        end
        def test(klass)
          klass::CONST
        end
        test(Foo)
    ");
    assert_contains_opcode("test", YARVINSN_getconstant);
    assert_snapshot!(inspect("test(Foo)"), @"1");
}

#[test]
fn test_expandarray_no_splat() {
    eval("
        def test(o)
          a, b = o
          [a, b]
        end
        test [3, 4]
    ");
    assert_contains_opcode("test", YARVINSN_expandarray);
    assert_snapshot!(inspect("test [3, 4]"), @"[3, 4]");
}

#[test]
fn test_expandarray_splat() {
    eval("
        def test(o)
          a, *b = o
          [a, b]
        end
        test [3, 4]
    ");
    assert_contains_opcode("test", YARVINSN_expandarray);
    assert_snapshot!(inspect("test [3, 4]"), @"[3, [4]]");
}

#[test]
fn test_expandarray_splat_post() {
    eval("
        def test(o)
          a, *b, c = o
          [a, b, c]
        end
        test [3, 4, 5]
    ");
    assert_contains_opcode("test", YARVINSN_expandarray);
    assert_snapshot!(inspect("test [3, 4, 5]"), @"[3, [4], 5]");
}

#[test]
fn test_constant_invalidation() {
    eval("
        class C; end
        def test = C
        test
        test
        C = 123
    ");
    assert_contains_opcode("test", YARVINSN_opt_getconstant_path);
    assert_snapshot!(inspect("test"), @"123");
}

#[test]
fn test_constant_path_invalidation() {
    eval("
        module A
          module B; end
        end
        module Foo
          C = 'Foo::C'
        end
        A::B = Foo
        def test = A::B::C
    ");
    assert_contains_opcode("test", YARVINSN_opt_getconstant_path);
    assert_snapshot!(inspect(r#"
        module A
          module B; end
        end
        module Foo
          C = "Foo::C"
        end
        module Bar
          C = "Bar::C"
        end
        A::B = Foo
        def test = A::B::C
        result = []
        result << test
        result << test
        A::B = Bar
        result << test
        result
    "#), @r#"["Foo::C", "Foo::C", "Bar::C"]"#);
}

#[test]
fn test_dupn() {
    eval("
        def test(array) = (array[1, 2] ||= :rhs)
        test([1, 1])
    ");
    assert_contains_opcode("test", YARVINSN_dupn);
    assert_snapshot!(inspect("
        one = [1, 1]
        start_empty = []
        [test(one), one, test(start_empty), start_empty]
    "), @"[[1], [1, 1], :rhs, [nil, :rhs]]");
}

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

#[test]
fn test_defined_with_defined_values() {
    eval("
        class Foo; end
        def bar; end
        $ruby = 1
        def test = [defined?(Foo), defined?(bar), defined?($ruby)]
        test
    ");
    assert_contains_opcode("test", YARVINSN_defined);
    assert_snapshot!(inspect("test"), @r#"["constant", "method", "global-variable"]"#);
}

#[test]
fn test_defined_with_undefined_values() {
    eval("
        def test = [defined?(FooUndef), defined?(bar_undef), defined?($ruby_undef)]
        test
    ");
    assert_contains_opcode("test", YARVINSN_defined);
    assert_snapshot!(inspect("test"), @"[nil, nil, nil]");
}

#[test]
fn test_defined_with_method_call() {
    eval(r#"
        def test = [defined?("x".reverse(1)), defined?("x".reverse(1).reverse)]
        test
    "#);
    assert_contains_opcode("test", YARVINSN_defined);
    assert_snapshot!(inspect(r#"test"#), @r#"["method", nil]"#);
}

#[test]
fn test_defined_method_raise() {
    assert_snapshot!(inspect(r#"
        class C
          def assert_equal expected, actual
            if expected != actual
              raise "NO"
            end
          end
          def test_defined_method
            assert_equal(nil, defined?("x".reverse(1).reverse))
          end
        end
        c = C.new
        result = []
        result << c.test_defined_method
        result << c.test_defined_method
        result << c.test_defined_method
        result
    "#), @"[nil, nil, nil]");
}

#[test]
fn test_defined_yield() {
    eval("
        def test = defined?(yield)
    ");
    assert_contains_opcode("test", YARVINSN_defined);
    assert_snapshot!(inspect("[test, test, test{}]"), @r#"[nil, nil, "yield"]"#);
}

#[test]
fn test_defined_yield_from_block() {
    assert_snapshot!(inspect("
        def test
          yield_self { yield_self { defined?(yield) } }
        end
        [test, test, test{}]
    "), @r#"[nil, nil, "yield"]"#);
}

#[test]
fn test_block_given_p() {
    assert_snapshot!(inspect("
        def test = block_given?
        [test, test, test{}]
    "), @"[false, false, true]");
}

#[test]
fn test_block_given_p_from_block() {
    assert_snapshot!(inspect("
        def test
          yield_self { yield_self { block_given? } }
        end
        [test, test, test{}]
    "), @"[false, false, true]");
}

#[test]
fn test_invokeblock_without_block_after_jit_call() {
    assert_snapshot!(inspect(r#"
        def test(*arr, &b)
          arr.class
          yield
        end
        test { }
        begin
          test
        rescue => e
          e.message
        end
    "#), @r#""no block given (yield)""#);
}

#[test]
fn test_putspecialobject_vm_core_and_cbase() {
    eval("
        def test
          alias bar test
          10
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_putspecialobject);
    assert_snapshot!(inspect("bar"), @"10");
}

#[test]
fn test_putspecialobject_const_base() {
    assert_snapshot!(inspect("
        Foo = 1
        def test = Foo
        test
        test
    "), @"1");
}

#[test]
fn test_branchnil() {
    eval("
        def test(x)
          x&.succ
        end
        test(0)
    ");
    assert_contains_opcode("test", YARVINSN_branchnil);
    assert_snapshot!(inspect("[test(1), test(nil)]"), @"[2, nil]");
}

#[test]
fn test_nil_nil() {
    eval("
        def test = nil.nil?
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test"), @"true");
}

#[test]
fn test_non_nil_nil() {
    eval("
        def test = 1.nil?
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test"), @"false");
}

#[test]
fn test_getspecial_last_match() {
    eval(r#"
        def test(str)
          str =~ /hello/
          $&
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#""hello""#);
}

#[test]
fn test_getspecial_match_pre() {
    eval(r#"
        def test(str)
          str =~ /world/
          $`
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#""hello ""#);
}

#[test]
fn test_getspecial_match_post() {
    eval(r#"
        def test(str)
          str =~ /hello/
          $'
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#"" world""#);
}

#[test]
fn test_getspecial_match_last_group() {
    eval(r#"
        def test(str)
          str =~ /(hello) (world)/
          $+
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#""world""#);
}

#[test]
fn test_getspecial_numbered_match_1() {
    eval(r#"
        def test(str)
          str =~ /(hello) (world)/
          $1
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#""hello""#);
}

#[test]
fn test_getspecial_numbered_match_2() {
    eval(r#"
        def test(str)
          str =~ /(hello) (world)/
          $2
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @r#""world""#);
}

#[test]
fn test_getspecial_numbered_match_nonexistent() {
    eval(r#"
        def test(str)
          str =~ /(hello)/
          $2
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @"nil");
}

#[test]
fn test_getspecial_no_match() {
    eval(r#"
        def test(str)
          str =~ /xyz/
          $&
        end
        test("hello world")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("hello world")"#), @"nil");
}

#[test]
fn test_getspecial_complex_pattern() {
    eval(r#"
        def test(str)
          str =~ /(\d+)/
          $1
        end
        test("abc123def")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("abc123def")"#), @r#""123""#);
}

#[test]
fn test_getspecial_multiple_groups() {
    eval(r#"
        def test(str)
          str =~ /(\d+)-(\d+)/
          $2
        end
        test("123-456")
    "#);
    assert_contains_opcode("test", YARVINSN_getspecial);
    assert_snapshot!(inspect(r#"test("123-456")"#), @r#""456""#);
}

#[test]
fn test_profile_under_nested_jit_call() {
    assert_snapshot!(inspect("
        def profile
          1 + 2
        end
        def jit_call(flag)
          if flag
            profile
          end
        end
        def entry(flag)
          jit_call(flag)
        end
        [entry(false), entry(false), entry(true)]
    "), @"[nil, nil, 3]");
}

#[test]
fn test_bop_redefined() {
    assert_snapshot!(inspect("
        def test
          1 + 2
        end
        test
        [test, Integer.class_eval { def +(_) = 100 }, test]
    "), @"[3, :+, 100]");
}

#[test]
fn test_bop_redefined_with_adjacent_patch_points() {
    assert_snapshot!(inspect("
        def test
          1 + 2 + 3 + 4 + 5
        end
        test
        [test, Integer.class_eval { def +(_) = 100 }, test]
    "), @"[15, :+, 100]");
}

#[test]
fn test_method_redefined_with_top_self() {
    assert_snapshot!(inspect(r#"
        def foo
          "original"
        end
        def test = foo
        test; test
        result1 = test
        def foo
          "redefined"
        end
        result2 = test
        [result1, result2]
    "#), @r#"["original", "redefined"]"#);
}

#[test]
fn test_method_redefined_with_module() {
    assert_snapshot!(inspect(r#"
        module Foo
          def self.foo = "original"
        end
        def test = Foo.foo
        test
        result1 = test
        def Foo.foo = "redefined"
        result2 = test
        [result1, result2]
    "#), @r#"["original", "redefined"]"#);
}

#[test]
fn test_module_name_with_guard_passes() {
    assert_snapshot!(inspect(r#"
        def test(mod)
          mod.name
        end
        test(String)
        test(Integer)
    "#), @r#""Integer""#);
}

#[test]
fn test_module_name_with_guard_side_exit() {
    assert_snapshot!(inspect(r#"
        class MyClass
          def name = "Bar"
        end
        def test(mod)
          mod.name
        end
        results = []
        results << test(String)
        results << test(Integer)
        results << test(MyClass.new)
        results
    "#), @r#"["String", "Integer", "Bar"]"#);
}

#[test]
fn test_objtostring_calls_to_s_on_non_strings() {
    assert_snapshot!(inspect(r##"
        results = []
        class Foo
          def to_s
            "foo"
          end
        end
        def test(str)
          "#{str}"
        end
        results << test(Foo.new)
        results << test(Foo.new)
        results
    "##), @r#"["foo", "foo"]"#);
}

#[test]
fn test_objtostring_rewrite_does_not_call_to_s_on_strings() {
    assert_snapshot!(inspect(r##"
        results = []
        class String
          def to_s
            "bad"
          end
        end
        def test(foo)
          "#{foo}"
        end
        results << test("foo")
        results << test("foo")
        results
    "##), @r#"["foo", "foo"]"#);
}

#[test]
fn test_objtostring_rewrite_does_not_call_to_s_on_string_subclasses() {
    assert_snapshot!(inspect(r##"
        results = []
        class StringSubclass < String
          def to_s
            "bad"
          end
        end
        foo = StringSubclass.new("foo")
        def test(str)
          "#{str}"
        end
        results << test(foo)
        results << test(foo)
        results
    "##), @r#"["foo", "foo"]"#);
}

#[test]
fn test_objtostring_profiled_string_fastpath() {
    assert_snapshot!(inspect(r##"
        def test(str)
          "#{str}"
        end
        test('foo'); test('foo')
    "##), @r#""foo""#);
}

#[test]
fn test_objtostring_profiled_string_subclass_fastpath() {
    assert_snapshot!(inspect(r##"
        class MyString < String; end
        def test(str)
          "#{str}"
        end
        foo = MyString.new("foo")
        test(foo); test(foo)
    "##), @r#""foo""#);
}

#[test]
fn test_objtostring_profiled_string_fastpath_exits_on_nonstring() {
    assert_snapshot!(inspect(r##"
        def test(str)
          "#{str}"
        end
        test('foo')
        test(1)
    "##), @r#""1""#);
}

#[test]
fn test_objtostring_profiled_nonstring_calls_to_s() {
    assert_snapshot!(inspect(r##"
        def test(str)
          "#{str}"
        end
        test([1,2,3]);
        test([1,2,3]);
    "##), @r#""[1, 2, 3]""#);
}

#[test]
fn test_objtostring_profiled_nonstring_guard_exits_when_string() {
    assert_snapshot!(inspect(r##"
        def test(str)
          "#{str}"
        end
        test([1,2,3]);
        test('foo');
    "##), @r#""foo""#);
}

#[test]
fn test_string_bytesize_with_guard() {
    assert_snapshot!(inspect("
        def test(str)
          str.bytesize
        end
        test('hello')
        test('world')
    "), @"5");
}

#[test]
fn test_string_bytesize_multibyte() {
    assert_snapshot!(inspect(r#"
        def test(s)
          s.bytesize
        end
        test("💎")
        test("💎")
    "#), @"4");
}

#[test]
fn test_nil_value_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(nil)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_nil_value_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(nil)
        test(nil)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(1)"), @"false");
}

#[test]
fn test_true_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(true)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(true)"), @"false");
}

#[test]
fn test_true_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(true)
        test(true)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_false_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(false)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(false)"), @"false");
}

#[test]
fn test_false_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(false)
        test(false)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_integer_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(1)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(2)"), @"false");
}

#[test]
fn test_integer_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(1)
        test(2)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_float_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(1.0)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(2.0)"), @"false");
}

#[test]
fn test_float_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(1.0)
        test(2.0)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_symbol_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(:foo)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(:bar)"), @"false");
}

#[test]
fn test_symbol_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(:foo)
        test(:bar)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_class_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(String)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(Integer)"), @"false");
}

#[test]
fn test_class_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(String)
        test(Integer)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_module_nil_opt_with_guard() {
    eval("
        def test(val) = val.nil?
        test(Enumerable)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(Kernel)"), @"false");
}

#[test]
fn test_module_nil_opt_with_guard_side_exit() {
    eval("
        def test(val) = val.nil?
        test(Enumerable)
        test(Kernel)
    ");
    assert_contains_opcode("test", YARVINSN_opt_nil_p);
    assert_snapshot!(inspect("test(nil)"), @"true");
}

#[test]
fn test_basic_object_guard_works_with_immediate() {
    assert_snapshot!(inspect("
        class Foo; end
        def test(val) = val.class
        test(Foo.new)
        test(Foo.new)
        test(nil)
    "), @"NilClass");
}

#[test]
fn test_basic_object_guard_works_with_false() {
    assert_snapshot!(inspect("
        class Foo; end
        def test(val) = val.class
        test(Foo.new)
        test(Foo.new)
        test(false)
    "), @"FalseClass");
}

#[test]
fn test_string_concat() {
    eval(r##"
        def test = "#{1}#{2}#{3}"
        test
    "##);
    assert_contains_opcode("test", YARVINSN_concatstrings);
    assert_snapshot!(inspect(r##"test"##), @r#""123""#);
}

#[test]
fn test_string_concat_empty() {
    eval(r##"
        def test = "#{}"
        test
    "##);
    assert_contains_opcode("test", YARVINSN_concatstrings);
    assert_snapshot!(inspect(r##"test"##), @r#""""#);
}

#[test]
fn test_regexp_interpolation() {
    eval(r##"
        def test = /#{1}#{2}#{3}/
        test
    "##);
    assert_contains_opcode("test", YARVINSN_toregexp);
    assert_snapshot!(inspect(r##"test"##), @"/123/");
}

#[test]
fn test_new_range_non_leaf() {
    assert_snapshot!(inspect("
        def jit_entry(v) = make_range_then_exit(v)
        def make_range_then_exit(v)
          range = (v..1)
          super rescue range
        end
        jit_entry(0)
        jit_entry(0)
        jit_entry(0/1r)
    "), @"(0/1)..1");
}

#[test]
fn test_raise_in_second_argument() {
    assert_snapshot!(inspect("
        def write(hash, key)
          hash[key] = raise rescue true
          hash
        end
        write({}, :warmup)
        write({}, :ok)
    "), @"{ok: true}");
}

#[test]
fn test_struct_set() {
    assert_snapshot!(inspect("
        C = Struct.new(:foo).new(1)
        def test
          C.foo = Object.new
          42
        end
        r = [test, test]
        C.freeze
        r << begin
          test
        rescue FrozenError
          :frozen_error
        end
    "), @"[42, 42, :frozen_error]");
}

#[test]
fn test_opt_case_dispatch() {
    eval("
        def test(x)
          case x
          when :foo
            true
          else
            false
          end
        end
        test(:warmup)
    ");
    assert_contains_opcode("test", YARVINSN_opt_case_dispatch);
    assert_snapshot!(inspect("[test(:foo), test(1)]"), @"[true, false]");
}

#[test]
fn test_stack_overflow() {
    assert_snapshot!(inspect("
        def recurse(n)
          return if n == 0
          recurse(n-1)
          nil
        end
        recurse(2)
        recurse(2)
        begin
          recurse(20_000)
        rescue SystemStackError
        end
    "), @"nil");
}

#[test]
fn test_invokeblock() {
    eval("
        def test
          yield
        end
        test { 41 }
    ");
    assert_contains_opcode("test", YARVINSN_invokeblock);
    assert_snapshot!(inspect("test { 42 }"), @"42");
}

#[test]
fn test_invokeblock_with_args() {
    eval("
        def test(x, y)
          yield x, y
        end
        test(1, 2) { |a, b| a + b }
    ");
    assert_contains_opcode("test", YARVINSN_invokeblock);
    assert_snapshot!(inspect("test(1, 2) { |a, b| a + b }"), @"3");
}

#[test]
fn test_invokeblock_no_block_given() {
    eval("
        def test
          yield rescue :error
        end
        test { }
    ");
    assert_contains_opcode("test", YARVINSN_invokeblock);
    assert_snapshot!(inspect("test"), @":error");
}

#[test]
fn test_invokeblock_multiple_yields() {
    eval("
        def test
          yield 1
          yield 2
          yield 3
        end
        test { |x| x }
    ");
    assert_contains_opcode("test", YARVINSN_invokeblock);
    assert_snapshot!(inspect("
        results = []
        test { |x| results << x }
        results
    "), @"[1, 2, 3]");
}

#[test]
fn test_ccall_variadic_with_multiple_args() {
    eval("
        def test
          a = []
          a.push(1, 2, 3)
          a
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test"), @"[1, 2, 3]");
}

#[test]
fn test_ccall_variadic_with_no_args() {
    eval("
        def test
          a = [1]
          a.push
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test"), @"[1]");
}

#[test]
fn test_ccall_variadic_with_no_args_causing_argument_error() {
    eval("
        def test
          format
        rescue ArgumentError
          :error
        end
        test
    ");
    assert_contains_opcode("test", YARVINSN_opt_send_without_block);
    assert_snapshot!(inspect("test"), @":error");
}

#[test]
fn test_allocating_in_hir_c_method_is() {
    eval("
        def a(f) = test(f)
        def test(f) = (f.new if f)
        def second = third
        def third = nil
        a(nil)
        a(nil)
        class Foo
        def self.new = :k
        end
        second
    ");
    assert_contains_opcode("test", YARVINSN_opt_new);
    assert_snapshot!(inspect("a(Foo)"), @":k");
}

#[test]
fn test_singleton_class_invalidation_annotated_ccall() {
    assert_snapshot!(inspect("
        def define_singleton(obj, define)
          if define
            [nil].reverse_each do
              class << obj
                def ==(_)
                  true
                end
              end
            end
          end
          false
        end
        def test(define)
          obj = BasicObject.new
          obj == define_singleton(obj, define)
        end
        result = []
        result << test(false)
        result << test(true)
        result
    "), @"[false, true]");
}

#[test]
fn test_singleton_class_invalidation_optimized_variadic_ccall() {
    assert_snapshot!(inspect("
        def define_singleton(arr, define)
          if define
            [nil].reverse_each do
              class << arr
                def push(x)
                  super(x * 1000)
                end
              end
            end
          end
          1
        end
        def test(define)
          arr = []
          val = define_singleton(arr, define)
          arr.push(val)
          arr[0]
        end
        result = []
        result << test(false)
        result << test(true)
        result
    "), @"[1, 1000]");
}

#[test]
fn test_is_a_string_special_case() {
    assert_snapshot!(inspect(r#"
        def test(x)
          x.is_a?(String)
        end
        test("foo")
        [test("bar"), test(1), test(false), test(:foo), test([]), test({})]
    "#), @"[true, false, false, false, false, false]");
}

#[test]
fn test_is_a_array_special_case() {
    assert_snapshot!(inspect("
        def test(x)
          x.is_a?(Array)
        end
        test([])
        [test([1,2,3]), test([]), test(1), test(false), test(:foo), test('foo'), test({})]
    "), @"[true, true, false, false, false, false, false]");
}

#[test]
fn test_is_a_hash_special_case() {
    assert_snapshot!(inspect("
        def test(x)
          x.is_a?(Hash)
        end
        test({})
        [test({:a => 'b'}), test({}), test(1), test(false), test(:foo), test([]), test('foo')]
    "), @"[true, true, false, false, false, false, false]");
}

#[test]
fn test_is_a_hash_subclass() {
    assert_snapshot!(inspect("
        class MyHash < Hash
        end
        def test(x)
          x.is_a?(Hash)
        end
        test({})
        test(MyHash.new)
    "), @"true");
}

#[test]
fn test_is_a_normal_case() {
    assert_snapshot!(inspect(r#"
        class MyClass
        end
        def test(x)
          x.is_a?(MyClass)
        end
        test("a")
        [test(MyClass.new), test("a")]
    "#), @"[true, false]");
}

#[test]
fn test_fixnum_div_zero() {
    eval("
        def test(n)
          n / 0
        rescue ZeroDivisionError => e
          e.message
        end
        test(0)
    ");
    assert_contains_opcode("test", YARVINSN_opt_div);
    assert_snapshot!(inspect(r#"test(0)"#), @r#""divided by 0""#);
}

#[test]
fn test_invokesuper_with_local_written_by_blockiseq() {
    assert_snapshot!(inspect(r#"
        class A
          def foo = "A"
        end
        class B < A
          def foo
            x = nil
            [nil].each do |_|
              x = super
            end
            x
          end
        end
        def test = B.new.foo
        test
        test
    "#), @r#""A""#);
}

#[test]
fn test_max_iseq_versions() {
    eval(&format!("
        TEST = -1
        def test = TEST

        # compile and invalidate MAX+1 times
        i = 0
        while i < {MAX_ISEQ_VERSIONS} + 1
          test; test # compile a version

          Object.send(:remove_const, :TEST)
          TEST = i

          i += 1
        end
    "));

    // It should not exceed MAX_ISEQ_VERSIONS
    let iseq = get_method_iseq("self", "test");
    let payload = get_or_create_iseq_payload(iseq);
    assert_eq!(payload.versions.len(), MAX_ISEQ_VERSIONS);

    // The last call should not discard the JIT code
    assert!(matches!(unsafe { payload.versions.last().unwrap().as_ref() }.status, IseqStatus::Compiled(_)));
}

#[test]
fn test_optional_arguments_side_exit() {
    assert_snapshot!(inspect("
        def test(a = (def foo = nil)) = a
        test
        [test, (undef :foo), test(1)]
    "), @"[:foo, nil, 1]");
}

#[test]
fn test_call_a_forwardable_method() {
    assert_snapshot!(inspect("
        def test_root = forwardable
        def forwardable(...) = Array.[](...)
        test_root
        test_root
    "), @"[]");
}

#[test]
fn test_send_on_heap_object_in_spilled_arg() {
    assert_snapshot!(inspect("
        def entry(a1, a2, a3, a4, a5, a6, a7, a8, a9)
          a9.itself.class
        end
        entry(1, 2, 3, 4, 5, 6, 7, 8, {})
        entry(1, 2, 3, 4, 5, 6, 7, 8, {})
    "), @"Hash");
}

#[test]
fn test_send_splat() {
    assert_snapshot!(inspect("
        def test(a, b) = [a, b]
        def entry(arr) = test(*arr)
        entry([1, 2])
        entry([1, 2])
    "), @"[1, 2]");
}

#[test]
fn test_send_kwarg() {
    assert_snapshot!(inspect("
        def test(a:, b:) = [a, b]
        def entry = test(b: 2, a: 1)
        entry
        entry
    "), @"[1, 2]");
}

#[test]
fn test_spilled_method_args() {
    assert_snapshot!(inspect("
        def foo(n1, n2, n3, n4, n5, n6, n7, n8, n9, n10)
          n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + n10
        end
        def test
          foo(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        end
        test
        test
    "), @"55");
}

#[test]
fn test_spilled_method_args_first_and_last() {
    assert_snapshot!(inspect("
        def a(n1,n2,n3,n4,n5,n6,n7,n8,n9) = n1+n9
        a(2,0,0,0,0,0,0,0,-1)
        a(2,0,0,0,0,0,0,0,-1)
    "), @"1");
}

#[test]
fn test_spilled_method_args_last() {
    assert_snapshot!(inspect("
        def a(n1,n2,n3,n4,n5,n6,n7,n8) = n8
        a(1,1,1,1,1,1,1,0)
        a(1,1,1,1,1,1,1,0)
    "), @"0");
}

#[test]
fn test_spilled_method_args_self() {
    assert_snapshot!(inspect("
        def a(n1,n2,n3,n4,n5,n6,n7,n8) = self
        a(1,0,0,0,0,0,0,0).to_s
        a(1,0,0,0,0,0,0,0).to_s
    "), @r#""main""#);
}

#[test]
fn test_spilled_param_new_array() {
    assert_snapshot!(inspect("
        def a(n1,n2,n3,n4,n5,n6,n7,n8) = [n8]
        a(0,0,0,0,0,0,0, :ok)
        a(0,0,0,0,0,0,0, :ok)
    "), @"[:ok]");
}

#[test]
fn test_forty_param_method() {
    assert_snapshot!(inspect("
        def foo(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,n40) = n40
        foo(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1)
        foo(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1)
    "), @"1");
}

#[test]
fn test_toplevel_local_after_eval() {
    assert_snapshot!(inspect("
        a = 1
        b = 2
        eval('b = 3')
        c = 4
        [a, b, c]
    "), @"[1, 3, 4]");
}

#[test]
fn test_send_exit_with_uninitialized_locals() {
    assert_snapshot!(inspect("
        def entry(init)
          function_stub_exit(init)
        end

        def function_stub_exit(init)
          uninitialized_local = 1 if init
          uninitialized_local
        end

        entry(true)
        entry(false)
    "), @"nil");
}

#[test]
fn test_invokebuiltin_dir_glob() {
    assert_snapshot!(inspect(r#"
        def test = Dir.glob(".")
        test
        test
    "#), @r#"["."]"#);
}

#[test]
fn test_profiled_fact() {
    assert_snapshot!(inspect("
        def fact(n)
          if n == 0
            return 1
          end
          return n * fact(n-1)
        end
        fact(1)
        [fact(0), fact(3), fact(6)]
    "), @"[1, 6, 720]");
}

#[test]
fn test_profiled_fib() {
    assert_snapshot!(inspect("
        def fib(n)
          if n < 2
            return n
          end
          return fib(n-1) + fib(n-2)
        end
        fib(3)
        [fib(0), fib(3), fib(4)]
    "), @"[0, 2, 3]");
}

#[test]
fn test_single_ractor_mode_invalidation() {
    assert_snapshot!(inspect(r#"
        C = Object.new

        def test
          C
        rescue Ractor::IsolationError
          "errored but not crashed"
        end

        test
        test

        Ractor.new {
          test
        }.value
    "#), @r#""errored but not crashed""#);
}

#[test]
fn test_ivar_attr_reader_optimization_with_multi_ractor_mode() {
    assert_snapshot!(inspect("
        class Foo
          class << self
            attr_accessor :bar

            def get_bar
              bar
            rescue Ractor::IsolationError
              42
            end
          end
        end

        Foo.bar = []

        def test
          Foo.get_bar
        end

        test
        test

        Ractor.new { test }.value
    "), @"42");
}

#[test]
fn test_ivar_get_with_multi_ractor_mode() {
    assert_snapshot!(inspect("
        class Foo
          def self.set_bar
            @bar = []
          end

          def self.bar
            @bar
          rescue Ractor::IsolationError
            42
          end
        end

        Foo.set_bar

        def test
          Foo.bar
        end

        test
        test

        Ractor.new { test }.value
    "), @"42");
}

#[test]
fn test_ivar_get_with_already_multi_ractor_mode() {
    assert_snapshot!(inspect("
        class Foo
          def self.set_bar
            @bar = []
          end

          def self.bar
            @bar
          rescue Ractor::IsolationError
            42
          end
        end

        Foo.set_bar
        r = Ractor.new {
          Ractor.receive
          Foo.bar
        }

        Foo.bar
        Foo.bar

        r << :go
        r.value
    "), @"42");
}

#[test]
fn test_ivar_set_with_multi_ractor_mode() {
    assert_snapshot!(inspect("
        class Foo
          def self.bar
            _foo = 1
            _bar = 2
            begin
              @bar = _foo + _bar
            rescue Ractor::IsolationError
              42
            end
          end
        end

        def test
          Foo.bar
        end

        test
        test

        Ractor.new { test }.value
    "), @"42");
}

#[test]
fn test_global_tracepoint() {
    assert_snapshot!(inspect("
        def foo = 1

        foo
        foo

        called = false

        tp = TracePoint.new(:return) { |event|
          if event.method_id == :foo
            called = true
          end
        }
        tp.enable do
          foo
        end
        called
    "), @"true");
}

#[test]
fn test_local_tracepoint() {
    assert_snapshot!(inspect("
        def foo = 1

        foo
        foo

        called = false

        tp = TracePoint.new(:return) { |_| called = true }
        tp.enable(target: method(:foo)) do
          foo
        end
        called
    "), @"true");
}
