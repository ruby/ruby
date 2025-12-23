# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS=test/ruby/test_zjit.rb

require 'test/unit'
require 'envutil'
require_relative '../lib/jit_support'
return unless JITSupport.zjit_supported?

class TestZJIT < Test::Unit::TestCase
  def test_enabled
    assert_runs 'false', <<~RUBY, zjit: false
      RubyVM::ZJIT.enabled?
    RUBY
    assert_runs 'true', <<~RUBY, zjit: true
      RubyVM::ZJIT.enabled?
    RUBY
  end

  def test_stats_enabled
    assert_runs 'false', <<~RUBY, stats: false
      RubyVM::ZJIT.stats_enabled?
    RUBY
    assert_runs 'true', <<~RUBY, stats: true
      RubyVM::ZJIT.stats_enabled?
    RUBY
  end

  def test_stats_quiet
    # Test that --zjit-stats-quiet collects stats but doesn't print them
    script = <<~RUBY
      def test = 42
      test
      test
      puts RubyVM::ZJIT.stats_enabled?
    RUBY

    stats_header = "***ZJIT: Printing ZJIT statistics on exit***"

    # With --zjit-stats, stats should be printed to stderr
    out, err, status = eval_with_jit(script, stats: true)
    assert_success(out, err, status)
    assert_includes(err, stats_header)
    assert_equal("true\n", out)

    # With --zjit-stats-quiet, stats should NOT be printed but still enabled
    out, err, status = eval_with_jit(script, stats: :quiet)
    assert_success(out, err, status)
    refute_includes(err, stats_header)
    assert_equal("true\n", out)

    # With --zjit-stats=<path>, stats should be printed to the path
    Tempfile.create("zjit-stats-") {|tmp|
      stats_file = tmp.path
      tmp.puts("Lorem ipsum dolor sit amet, consectetur adipiscing elit, ...")
      tmp.close

      out, err, status = eval_with_jit(script, stats: stats_file)
      assert_success(out, err, status)
      refute_includes(err, stats_header)
      assert_equal("true\n", out)
      assert_equal stats_header, File.open(stats_file) {|f| f.gets(chomp: true)}, "should be overwritten"
    }
  end

  def test_enable_through_env
    child_env = {'RUBY_YJIT_ENABLE' => nil, 'RUBY_ZJIT_ENABLE' => '1'}
    assert_in_out_err([child_env, '-v'], '') do |stdout, stderr|
      assert_includes(stdout.first, '+ZJIT')
      assert_equal([], stderr)
    end
  end

  def test_zjit_enable
    # --disable-all is important in case the build/environment has YJIT enabled by
    # default through e.g. -DYJIT_FORCE_ENABLE. Can't enable ZJIT when YJIT is on.
    assert_separately(["--disable-all"], <<~'RUBY')
      refute_predicate RubyVM::ZJIT, :enabled?
      refute_predicate RubyVM::ZJIT, :stats_enabled?
      refute_includes RUBY_DESCRIPTION, "+ZJIT"

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      refute_predicate RubyVM::ZJIT, :stats_enabled?
      assert_includes RUBY_DESCRIPTION, "+ZJIT"
    RUBY
  end

  def test_zjit_disable
    assert_separately(["--zjit", "--zjit-disable"], <<~'RUBY')
      refute_predicate RubyVM::ZJIT, :enabled?
      refute_includes RUBY_DESCRIPTION, "+ZJIT"

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      assert_includes RUBY_DESCRIPTION, "+ZJIT"
    RUBY
  end

  def test_zjit_enable_respects_existing_options
    assert_separately(['--zjit-disable', '--zjit-stats-quiet'], <<~RUBY)
      refute_predicate RubyVM::ZJIT, :enabled?
      assert_predicate RubyVM::ZJIT, :stats_enabled?

      RubyVM::ZJIT.enable

      assert_predicate RubyVM::ZJIT, :enabled?
      assert_predicate RubyVM::ZJIT, :stats_enabled?
    RUBY
  end

  def test_call_itself
    assert_compiles '42', <<~RUBY, call_threshold: 2
      def test = 42.itself
      test
      test
    RUBY
  end

  def test_nil
    assert_compiles 'nil', %q{
      def test = nil
      test
    }
  end

  def test_putobject
    assert_compiles '1', %q{
      def test = 1
      test
    }
  end

  def test_putstring
    assert_compiles '""', %q{
      def test = "#{""}"
      test
    }, insns: [:putstring]
  end

  def test_putchilldedstring
    assert_compiles '""', %q{
      def test = ""
      test
    }, insns: [:putchilledstring]
  end

  def test_leave_param
    assert_compiles '5', %q{
      def test(n) = n
      test(5)
    }
  end

  def test_getglobal_with_warning
    assert_compiles('"rescued"', %q{
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
    }, insns: [:getglobal])
  end

  def test_setglobal
    assert_compiles '1', %q{
      def test
        $a = 1
        $a
      end

      test
    }, insns: [:setglobal]
  end

  def test_string_intern
    assert_compiles ':foo123', %q{
      def test
        :"foo#{123}"
      end

      test
    }, insns: [:intern]
  end

  def test_duphash
    assert_compiles '{a: 1}', %q{
      def test
        {a: 1}
      end

      test
    }, insns: [:duphash]
  end

  def test_pushtoarray
    assert_compiles '[1, 2, 3]', %q{
      def test
        [*[], 1, 2, 3]
      end
      test
    }, insns: [:pushtoarray]
  end

  def test_splatarray_new_array
    assert_compiles '[1, 2, 3]', %q{
      def test a
        [*a, 3]
      end
      test [1, 2]
    }, insns: [:splatarray]
  end

  def test_splatarray_existing_array
    assert_compiles '[1, 2, 3]', %q{
      def foo v
        [1, 2, v]
      end
      def test a
        foo(*a)
      end
      test [3]
    }, insns: [:splatarray]
  end

  def test_concattoarray
    assert_compiles '[1, 2, 3]', %q{
      def test(*a)
        [1, 2, *a]
      end
      test 3
    }, insns: [:concattoarray]
  end

  def test_definedivar
    assert_compiles '[nil, "instance-variable", nil]', %q{
      def test
        v0 = defined?(@a)
        @a = nil
        v1 = defined?(@a)
        remove_instance_variable :@a
        v2 = defined?(@a)
        [v0, v1, v2]
      end
      test
    }, insns: [:definedivar]
  end

  def test_setglobal_with_trace_var_exception
    assert_compiles '"rescued"', %q{
      def test
        $a = 1
      rescue
        "rescued"
      end

      trace_var(:$a) { raise }
      test
    }, insns: [:setglobal]
  end

  def test_toplevel_binding
    # Not using assert_compiles, which doesn't use the toplevel frame for `test_script`.
    out, err, status = eval_with_jit(%q{
      a = 1
      b = 2
      TOPLEVEL_BINDING.local_variable_set(:b, 3)
      c = 4
      print [a, b, c]
    })
    assert_success(out, err, status)
    assert_equal "[1, 3, 4]", out
  end

  def test_toplevel_local_after_eval
    # Not using assert_compiles, which doesn't use the toplevel frame for `test_script`.
    out, err, status = eval_with_jit(%q{
      a = 1
      b = 2
      eval('b = 3')
      c = 4
      print [a, b, c]
    })
    assert_success(out, err, status)
    assert_equal "[1, 3, 4]", out
  end

  def test_getlocal_after_eval
    assert_compiles '2', %q{
      def test
        a = 1
        eval('a = 2')
        a
      end
      test
    }
  end

  def test_getlocal_after_instance_eval
    assert_compiles '2', %q{
      def test
        a = 1
        instance_eval('a = 2')
        a
      end
      test
    }
  end

  def test_getlocal_after_module_eval
    assert_compiles '2', %q{
      def test
        a = 1
        Kernel.module_eval('a = 2')
        a
      end
      test
    }
  end

  def test_getlocal_after_class_eval
    assert_compiles '2', %q{
      def test
        a = 1
        Kernel.class_eval('a = 2')
        a
      end
      test
    }
  end

  def test_setlocal
    assert_compiles '3', %q{
      def test(n)
        m = n
        m
      end
      test(3)
    }
  end

  def test_return_nonparam_local
    # Use dead code (if false) to create a local without initialization instructions.
    assert_compiles 'nil', %q{
      def foo(a)
        if false
          x = nil
        end
        x
      end
      def test = foo(1)
      test
      test
    }, call_threshold: 2
  end

  def test_nonparam_local_nil_in_jit_call
    # Non-parameter locals must be initialized to nil in JIT-to-JIT calls.
    # Use dead code (if false) to create locals without initialization instructions.
    # Then eval a string that accesses the uninitialized locals.
    assert_compiles '["x", "x", "x", "x"]', %q{
      def f(a)
        a ||= 1
        if false; b = 1; end
        eval("-> { p 'x#{b}' }")
      end

      4.times.map { f(1).call }
    }, call_threshold: 2
  end

  def test_setlocal_on_eval
    assert_compiles '1', %q{
      @b = binding
      eval('a = 1', @b)
      eval('a', @b)
    }
  end

  def test_optional_arguments
    assert_compiles '[[1, 2, 3], [10, 20, 3], [100, 200, 300]]', %q{
      def test(a, b = 2, c = 3)
        [a, b, c]
      end
      [test(1), test(10, 20), test(100, 200, 300)]
    }
  end

  def test_optional_arguments_setlocal
    assert_compiles '[[2, 2], [1, nil]]', %q{
      def test(a = (b = 2))
        [a, b]
      end
      [test, test(1)]
    }
  end

  def test_optional_arguments_cyclic
    assert_compiles '[nil, 1]', %q{
      test = proc { |a=a| a }
      [test.call, test.call(1)]
    }
  end

  def test_optional_arguments_side_exit
    # This leads to FailedOptionalArguments, so not using assert_compiles
    assert_runs '[:foo, nil, 1]', %q{
      def test(a = (def foo = nil)) = a
      [test, (undef :foo), test(1)]
    }
  end

  def test_getblockparamproxy
    assert_compiles '1', %q{
      def test(&block)
        0.then(&block)
      end
      test { 1 }
    }, insns: [:getblockparamproxy]
  end

  def test_call_a_forwardable_method
    assert_runs '[]', %q{
      def test_root = forwardable
      def forwardable(...) = Array.[](...)
      test_root
      test_root
    }, call_threshold: 2
  end

  def test_setlocal_on_eval_with_spill
    assert_compiles '1', %q{
      @b = binding
      eval('a = 1; itself', @b)
      eval('a', @b)
    }
  end

  def test_nested_local_access
    assert_compiles '[1, 2, 3]', %q{
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
    }, call_threshold: 3, insns: [:getlocal, :setlocal, :getlocal_WC_0, :setlocal_WC_1]
  end

  def test_send_with_local_written_by_blockiseq
    assert_compiles '[1, 2]', %q{
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
    }, call_threshold: 2
  end

  def test_send_without_block
    assert_compiles '[1, 2, 3]', %q{
      def foo = 1
      def bar(a) = a - 1
      def baz(a, b) = a - b

      def test1 = foo
      def test2 = bar(3)
      def test3 = baz(4, 1)

      [test1, test2, test3]
    }
  end

  def test_send_with_six_args
    assert_compiles '[1, 2, 3, 4, 5, 6]', %q{
      def foo(a1, a2, a3, a4, a5, a6)
        [a1, a2, a3, a4, a5, a6]
      end

      def test
        foo(1, 2, 3, 4, 5, 6)
      end

      test # profile send
      test
    }, call_threshold: 2
  end

  def test_send_on_heap_object_in_spilled_arg
    # This leads to a register spill, so not using `assert_compiles`
    assert_runs 'Hash', %q{
      def entry(a1, a2, a3, a4, a5, a6, a7, a8, a9)
        a9.itself.class
      end

      entry(1, 2, 3, 4, 5, 6, 7, 8, {}) # profile
      entry(1, 2, 3, 4, 5, 6, 7, 8, {})
    }, call_threshold: 2
  end

  def test_send_exit_with_uninitialized_locals
    assert_runs 'nil', %q{
      def entry(init)
        function_stub_exit(init)
      end

      def function_stub_exit(init)
        uninitialized_local = 1 if init
        uninitialized_local
      end

      entry(true) # profile and set 1 to the local slot
      entry(false)
    }, call_threshold: 2, allowed_iseqs: 'entry@-e:2'
  end

  def test_send_optional_arguments
    assert_compiles '[[1, 2], [3, 4]]', %q{
      def test(a, b = 2) = [a, b]
      def entry = [test(1), test(3, 4)]
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_nil_block_arg
    assert_compiles 'false', %q{
      def test = block_given?
      def entry = test(&nil)
      test
    }
  end

  def test_send_symbol_block_arg
    assert_compiles '["1", "2"]', %q{
      def test = [1, 2].map(&:to_s)
      test
    }
  end

  def test_send_variadic_with_block
    assert_compiles '[[1, "a"], [2, "b"], [3, "c"]]', %q{
      A = [1, 2, 3]
      B = ["a", "b", "c"]

      def test
        result = []
        A.zip(B) { |x, y| result << [x, y] }
        result
      end

      test; test
    }, call_threshold: 2
  end

  def test_send_splat
    assert_runs '[1, 2]', %q{
      def test(a, b) = [a, b]
      def entry(arr) = test(*arr)
      entry([1, 2])
    }
  end

  def test_send_kwarg
    assert_runs '[1, 2]', %q{
      def test(a:, b:) = [a, b]
      def entry = test(b: 2, a: 1) # change order
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_optional
    assert_compiles '[1, 2]', %q{
      def test(a: 1, b: 2) = [a, b]
      def entry = test
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_optional_too_many
    assert_compiles '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]', %q{
      def test(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10) = [a, b, c, d, e, f, g, h, i, j]
      def entry = test
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_required_and_optional
    assert_compiles '[3, 2]', %q{
      def test(a:, b: 2) = [a, b]
      def entry = test(a: 3)
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_to_hash
    assert_compiles '{a: 3}', %q{
      def test(hash) = hash
      def entry = test(a: 3)
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_to_ccall
    assert_compiles '["a", "b", "c"]', %q{
      def test(s) = s.each_line(chomp: true).to_a
      def entry = test(%(a\nb\nc))
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_and_block_to_ccall
    assert_compiles '["a", "b", "c"]', %q{
      def test(s)
        a = []
        s.each_line(chomp: true) { |l| a << l }
        a
      end
      def entry = test(%(a\nb\nc))
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwarg_with_too_many_args_to_c_call
    assert_compiles '"a b c d {kwargs: :e}"', %q{
      def test(a:, b:, c:, d:, e:) = sprintf("%s %s %s %s %s", a, b, c, d, kwargs: e)
      def entry = test(e: :e, d: :d, c: :c, a: :a, b: :b)
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwsplat
    assert_compiles '3', %q{
      def test(a:) = a
      def entry = test(**{a: 3})
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_kwrest
    assert_compiles '{a: 3}', %q{
      def test(**kwargs) = kwargs
      def entry = test(a: 3)
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_req_kwreq
    assert_compiles '[1, 3]', %q{
      def test(a, c:) = [a, c]
      def entry = test(1, c: 3)
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_req_opt_kwreq
    assert_compiles '[[1, 2, 3], [-1, -2, -3]]', %q{
      def test(a, b = 2, c:) = [a, b, c]
      def entry = [test(1, c: 3), test(-1, -2, c: -3)] # specify all, change kw order
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_req_opt_kwreq_kwopt
    assert_compiles '[[1, 2, 3, 4], [-1, -2, -3, -4]]', %q{
      def test(a, b = 2, c:, d: 4) = [a, b, c, d]
      def entry = [test(1, c: 3), test(-1, -2, d: -4, c: -3)] # specify all, change kw order
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_unexpected_keyword
    assert_compiles ':error', %q{
      def test(a: 1) = a*2
      def entry
        test(z: 2)
      rescue ArgumentError
        :error
      end

      entry
      entry
    }, call_threshold: 2
  end

  def test_send_all_arg_types
    assert_compiles '[:req, :opt, :post, :kwr, :kwo, true]', %q{
      def test(a, b = :opt, c, d:, e: :kwo) = [a, b, c, d, e, block_given?]
      def entry = test(:req, :post, d: :kwr) {}
      entry
      entry
    }, call_threshold: 2
  end

  def test_send_ccall_variadic_with_different_receiver_classes
    assert_compiles '[true, true]', %q{
      def test(obj) = obj.start_with?("a")
      [test("abc"), test(:abc)]
    }, call_threshold: 2
  end

  def test_forwardable_iseq
    assert_compiles '1', %q{
      def test(...) = 1
      test
    }
  end

  def test_sendforward
    assert_compiles '[1, 2]', %q{
      def callee(a, b) = [a, b]
      def test(...) = callee(...)
      test(1, 2)
    }, insns: [:sendforward]
  end

  def test_iseq_with_optional_arguments
    assert_compiles '[[1, 2], [3, 4]]', %q{
      def test(a, b = 2) = [a, b]
      [test(1), test(3, 4)]
    }
  end

  def test_invokesuper
    assert_compiles '[6, 60]', %q{
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
    }
  end

  def test_invokesuper_with_local_written_by_blockiseq
    # Using `assert_runs` because we don't compile invokeblock yet
    assert_runs '3', %q{
      class Foo
        def test
          yield
        end
      end

      class Bar < Foo
        def test
          a = 1
          super do
            a += 2
          end
          a
        end
      end

      Bar.new.test
    }
  end

  def test_invokebuiltin
    # Not using assert_compiles due to register spill
    assert_runs '["."]', %q{
      def test = Dir.glob(".")
      test
    }
  end

  def test_invokebuiltin_delegate
    assert_compiles '[[], true]', %q{
      def test = [].clone(freeze: true)
      r = test
      [r, r.frozen?]
    }
  end

  def test_opt_plus_const
    assert_compiles '3', %q{
      def test = 1 + 2
      test # profile opt_plus
      test
    }, call_threshold: 2
  end

  def test_opt_plus_fixnum
    assert_compiles '3', %q{
      def test(a, b) = a + b
      test(0, 1) # profile opt_plus
      test(1, 2)
    }, call_threshold: 2
  end

  def test_opt_plus_chain
    assert_compiles '6', %q{
      def test(a, b, c) = a + b + c
      test(0, 1, 2) # profile opt_plus
      test(1, 2, 3)
    }, call_threshold: 2
  end

  def test_opt_plus_left_imm
    assert_compiles '3', %q{
      def test(a) = 1 + a
      test(1) # profile opt_plus
      test(2)
    }, call_threshold: 2
  end

  def test_opt_plus_type_guard_exit
    assert_compiles '[3, 3.0]', %q{
      def test(a) = 1 + a
      test(1) # profile opt_plus
      [test(2), test(2.0)]
    }, call_threshold: 2
  end

  def test_opt_plus_type_guard_exit_with_locals
    assert_compiles '[6, 6.0]', %q{
      def test(a)
        local = 3
        1 + a + local
      end
      test(1) # profile opt_plus
      [test(2), test(2.0)]
    }, call_threshold: 2
  end

  def test_opt_plus_type_guard_nested_exit
    assert_compiles '[4, 4.0]', %q{
      def side_exit(n) = 1 + n
      def jit_frame(n) = 1 + side_exit(n)
      def entry(n) = jit_frame(n)
      entry(2) # profile send
      [entry(2), entry(2.0)]
    }, call_threshold: 2
  end

  def test_opt_plus_type_guard_nested_exit_with_locals
    assert_compiles '[9, 9.0]', %q{
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
    }, call_threshold: 2
  end

  # Test argument ordering
  def test_opt_minus
    assert_compiles '2', %q{
      def test(a, b) = a - b
      test(2, 1) # profile opt_minus
      test(6, 4)
    }, call_threshold: 2
  end

  def test_opt_mult
    assert_compiles '6', %q{
      def test(a, b) = a * b
      test(1, 2) # profile opt_mult
      test(2, 3)
    }, call_threshold: 2
  end

  def test_opt_mult_overflow
    assert_compiles '[6, -6, 9671406556917033397649408, -9671406556917033397649408, 21267647932558653966460912964485513216]', %q{
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
    }, call_threshold: 2
  end

  def test_opt_eq
    assert_compiles '[true, false]', %q{
      def test(a, b) = a == b
      test(0, 2) # profile opt_eq
      [test(1, 1), test(0, 1)]
    }, insns: [:opt_eq], call_threshold: 2
  end

  def test_opt_eq_with_minus_one
    assert_compiles '[false, true]', %q{
      def test(a) = a == -1
      test(1) # profile opt_eq
      [test(0), test(-1)]
    }, insns: [:opt_eq], call_threshold: 2
  end

  def test_opt_neq_dynamic
    # TODO(max): Don't split this test; instead, run all tests with and without
    # profiling.
    assert_compiles '[false, true]', %q{
      def test(a, b) = a != b
      test(0, 2) # profile opt_neq
      [test(1, 1), test(0, 1)]
    }, insns: [:opt_neq], call_threshold: 1
  end

  def test_opt_neq_fixnum
    assert_compiles '[false, true]', %q{
      def test(a, b) = a != b
      test(0, 2) # profile opt_neq
      [test(1, 1), test(0, 1)]
    }, call_threshold: 2
  end

  def test_opt_lt
    assert_compiles '[true, false, false]', %q{
      def test(a, b) = a < b
      test(2, 3) # profile opt_lt
      [test(0, 1), test(0, 0), test(1, 0)]
    }, insns: [:opt_lt], call_threshold: 2
  end

  def test_opt_lt_with_literal_lhs
    assert_compiles '[false, false, true]', %q{
      def test(n) = 2 < n
      test(2) # profile opt_lt
      [test(1), test(2), test(3)]
    }, insns: [:opt_lt], call_threshold: 2
  end

  def test_opt_le
    assert_compiles '[true, true, false]', %q{
      def test(a, b) = a <= b
      test(2, 3) # profile opt_le
      [test(0, 1), test(0, 0), test(1, 0)]
    }, insns: [:opt_le], call_threshold: 2
  end

  def test_opt_gt
    assert_compiles '[false, false, true]', %q{
      def test(a, b) = a > b
      test(2, 3) # profile opt_gt
      [test(0, 1), test(0, 0), test(1, 0)]
    }, insns: [:opt_gt], call_threshold: 2
  end

  def test_opt_empty_p
    assert_compiles('[false, false, true]', <<~RUBY, insns: [:opt_empty_p])
      def test(x) = x.empty?
      return test([1]), test("1"), test({})
    RUBY
  end

  def test_opt_succ
    assert_compiles('[0, "B"]', <<~RUBY, insns: [:opt_succ])
      def test(obj) = obj.succ
      return test(-1), test("A")
    RUBY
  end

  def test_opt_and
    assert_compiles('[1, [3, 2, 1]]', <<~RUBY, insns: [:opt_and])
      def test(x, y) = x & y
      return test(0b1101, 3), test([3, 2, 1, 4], [8, 1, 2, 3])
    RUBY
  end

  def test_opt_or
    assert_compiles('[11, [3, 2, 1]]', <<~RUBY, insns: [:opt_or])
      def test(x, y) = x | y
      return test(0b1000, 3), test([3, 2, 1], [1, 2, 3])
    RUBY
  end

  def test_fixnum_and
    assert_compiles '[1, 2, 4]', %q{
      def test(a, b) = a & b
      [
        test(5, 3),
        test(0b011, 0b110),
        test(-0b011, 0b110)
      ]
    }, call_threshold: 2, insns: [:opt_and]
  end

  def test_fixnum_and_side_exit
    assert_compiles '[2, 2, false]', %q{
      def test(a, b) = a & b
      [
        test(2, 2),
        test(0b011, 0b110),
        test(true, false)
      ]
    }, call_threshold: 2, insns: [:opt_and]
  end

  def test_fixnum_or
    assert_compiles '[7, 3, -3]', %q{
      def test(a, b) = a | b
      [
        test(5, 3),
        test(1, 2),
        test(1, -4)
      ]
    }, call_threshold: 2, insns: [:opt_or]
  end

  def test_fixnum_or_side_exit
    assert_compiles '[3, 2, true]', %q{
      def test(a, b) = a | b
      [
        test(1, 2),
        test(2, 2),
        test(true, false)
      ]
    }, call_threshold: 2, insns: [:opt_or]
  end

  def test_fixnum_xor
    assert_compiles '[6, -8, 3]', %q{
      def test(a, b) = a ^ b
      [
        test(5, 3),
        test(-5, 3),
        test(1, 2)
      ]
    }, call_threshold: 2
  end

  def test_fixnum_xor_side_exit
    assert_compiles '[6, 6, true]', %q{
      def test(a, b) = a ^ b
      [
        test(5, 3),
        test(5, 3),
        test(true, false)
      ]
    }, call_threshold: 2
  end

  def test_fixnum_mul
    assert_compiles '12', %q{
      C = 3
      def test(n) = C * n
      test(4)
      test(4)
      test(4)
    }, call_threshold: 2, insns: [:opt_mult]
  end

  def test_fixnum_div
    assert_compiles '12', %q{
      C = 48
      def test(n) = C / n
      test(4)
      test(4)
    }, call_threshold: 2, insns: [:opt_div]
  end

  def test_fixnum_floor
    assert_compiles '0', %q{
      C = 3
      def test(n) = C / n
      test(4)
      test(4)
    }, call_threshold: 2, insns: [:opt_div]
  end

  def test_fixnum_div_zero
    assert_runs '"divided by 0"', %q{
      def test(n)
        n / 0
      rescue ZeroDivisionError => e
        e.message
      end

      test(0)
      test(0)
    }, call_threshold: 2, insns: [:opt_div]
  end

  def test_opt_not
    assert_compiles('[true, true, false]', <<~RUBY, insns: [:opt_not])
      def test(obj) = !obj
      return test(nil), test(false), test(0)
    RUBY
  end

  def test_opt_regexpmatch2
    assert_compiles('[1, nil]', <<~RUBY, insns: [:opt_regexpmatch2])
      def test(haystack) = /needle/ =~ haystack
      return test("kneedle"), test("")
    RUBY
  end

  def test_opt_ge
    assert_compiles '[false, true, true]', %q{
      def test(a, b) = a >= b
      test(2, 3) # profile opt_ge
      [test(0, 1), test(0, 0), test(1, 0)]
    }, insns: [:opt_ge], call_threshold: 2
  end

  def test_opt_new_does_not_push_frame
    assert_compiles 'nil', %q{
      class Foo
        attr_reader :backtrace

        def initialize
          @backtrace = caller
        end
      end
      def test = Foo.new

      foo = test
      foo.backtrace.find do |frame|
        frame.include?('Class#new')
      end
    }, insns: [:opt_new]
  end

  def test_opt_new_with_redefined
    assert_compiles '"foo"', %q{
      class Foo
        def self.new = "foo"

        def initialize = raise("unreachable")
      end
      def test = Foo.new

      test
    }, insns: [:opt_new]
  end

  def test_opt_new_invalidate_new
    assert_compiles '["Foo", "foo"]', %q{
      class Foo; end
      def test = Foo.new
      test; test
      result = [test.class.name]
      def Foo.new = "foo"
      result << test
      result
    }, insns: [:opt_new], call_threshold: 2
  end

  def test_opt_new_with_custom_allocator
    assert_compiles '"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"', %q{
      require "digest"
      def test = Digest::SHA256.new.hexdigest
      test; test
    }, insns: [:opt_new], call_threshold: 2
  end

  def test_opt_new_with_custom_allocator_raises
    assert_compiles '[42, 42]', %q{
      require "digest"
      class C < Digest::Base; end
      def test
        begin
          Digest::Base.new
        rescue NotImplementedError
          42
        end
      end
      [test, test]
    }, insns: [:opt_new], call_threshold: 2
  end

  def test_opt_newarray_send_include_p
    assert_compiles '[true, false]', %q{
      def test(x)
        [:y, 1, Object.new].include?(x)
      end
      [test(1), test("n")]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_include_p_redefined
    assert_compiles '[:true, :false]', %q{
      class Array
        alias_method :old_include?, :include?
        def include?(x)
          old_include?(x) ? :true : :false
        end
      end

      def test(x)
        [:y, 1, Object.new].include?(x)
      end
      [test(1), test("n")]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_duparray_send_include_p
    assert_compiles '[true, false]', %q{
      def test(x)
        [:y, 1].include?(x)
      end
      [test(1), test("n")]
    }, insns: [:opt_duparray_send], call_threshold: 1
  end

  def test_opt_duparray_send_include_p_redefined
    assert_compiles '[:true, :false]', %q{
      class Array
        alias_method :old_include?, :include?
        def include?(x)
          old_include?(x) ? :true : :false
        end
      end

      def test(x)
        [:y, 1].include?(x)
      end
      [test(1), test("n")]
    }, insns: [:opt_duparray_send], call_threshold: 1
  end

  def test_opt_newarray_send_pack_buffer
    assert_compiles '["ABC", "ABC", "ABC", "ABC"]', %q{
      def test(num, buffer)
        [num].pack('C', buffer:)
      end
      buf = ""
      [test(65, buf), test(66, buf), test(67, buf), buf]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_pack_buffer_redefined
    assert_compiles '["b", "A"]', %q{
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
      buf = ""
      [test(65, buf), buf]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_hash
    assert_compiles 'Integer', %q{
      def test(x)
        [1, 2, x].hash
      end
      test(20).class
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_hash_redefined
    assert_compiles '42', %q{
      Array.class_eval { def hash = 42 }

      def test(x)
        [1, 2, x].hash
      end
      test(20)
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_max
    assert_compiles '[20, 40]', %q{
      def test(a,b) = [a,b].max
      [test(10, 20), test(40, 30)]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_opt_newarray_send_max_redefined
    assert_compiles '[60, 90]', %q{
      class Array
        alias_method :old_max, :max
        def max
          old_max * 2
        end
      end

      def test(a,b) = [a,b].max
      [test(15, 30), test(45, 35)]
    }, insns: [:opt_newarray_send], call_threshold: 1
  end

  def test_new_hash_empty
    assert_compiles '{}', %q{
      def test = {}
      test
    }, insns: [:newhash]
  end

  def test_new_hash_nonempty
    assert_compiles '{"key" => "value", 42 => 100}', %q{
      def test
        key = "key"
        value = "value"
        num = 42
        result = 100
        {key => value, num => result}
      end
      test
    }, insns: [:newhash]
  end

  def test_new_hash_single_key_value
    assert_compiles '{"key" => "value"}', %q{
      def test = {"key" => "value"}
      test
    }, insns: [:newhash]
  end

  def test_new_hash_with_computation
    assert_compiles '{"sum" => 5, "product" => 6}', %q{
      def test(a, b)
        {"sum" => a + b, "product" => a * b}
      end
      test(2, 3)
    }, insns: [:newhash]
  end

  def test_new_hash_with_user_defined_hash_method
    assert_runs 'true', %q{
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
    }
  end

  def test_new_hash_with_user_hash_method_exception
    assert_runs 'RuntimeError', %q{
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
    }
  end

  def test_new_hash_with_user_eql_method_exception
    assert_runs 'RuntimeError', %q{
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
    }
  end

  def test_opt_hash_freeze
    assert_compiles "[{}, 5]", %q{
      def test = {}.freeze
      result = [test]
      class Hash
        def freeze = 5
      end
      result << test
    }, insns: [:opt_hash_freeze], call_threshold: 1
  end

  def test_opt_hash_freeze_rewritten
    assert_compiles "5", %q{
      class Hash
        def freeze = 5
      end
      def test = {}.freeze
      test
    }, insns: [:opt_hash_freeze], call_threshold: 1
  end

  def test_opt_aset_hash
    assert_compiles '42', %q{
      def test(h, k, v)
        h[k] = v
      end
      h = {}
      test(h, :key, 42)
      test(h, :key, 42)
      h[:key]
    }, call_threshold: 2, insns: [:opt_aset]
  end

  def test_opt_aset_hash_returns_value
    assert_compiles '100', %q{
      def test(h, k, v)
        h[k] = v
      end
      test({}, :key, 100)
      test({}, :key, 100)
    }, call_threshold: 2
  end

  def test_opt_aset_hash_string_key
    assert_compiles '"bar"', %q{
      def test(h, k, v)
        h[k] = v
      end
      h = {}
      test(h, "foo", "bar")
      test(h, "foo", "bar")
      h["foo"]
    }, call_threshold: 2
  end

  def test_opt_aset_hash_subclass
    assert_compiles '42', %q{
      class MyHash < Hash; end
      def test(h, k, v)
        h[k] = v
      end
      h = MyHash.new
      test(h, :key, 42)
      test(h, :key, 42)
      h[:key]
    }, call_threshold: 2
  end

  def test_opt_aset_hash_too_few_args
    assert_compiles '"ArgumentError"', %q{
      def test(h)
        h.[]= 123
      rescue ArgumentError
        "ArgumentError"
      end
      test({})
      test({})
    }, call_threshold: 2
  end

  def test_opt_aset_hash_too_many_args
    assert_compiles '"ArgumentError"', %q{
      def test(h)
        h[:a, :b] = :c
      rescue ArgumentError
        "ArgumentError"
      end
      test({})
      test({})
    }, call_threshold: 2
  end

  def test_opt_ary_freeze
    assert_compiles "[[], 5]", %q{
      def test = [].freeze
      result = [test]
      class Array
        def freeze = 5
      end
      result << test
    }, insns: [:opt_ary_freeze], call_threshold: 1
  end

  def test_opt_ary_freeze_rewritten
    assert_compiles "5", %q{
      class Array
        def freeze = 5
      end
      def test = [].freeze
      test
    }, insns: [:opt_ary_freeze], call_threshold: 1
  end

  def test_opt_str_freeze
    assert_compiles "[\"\", 5]", %q{
      def test = ''.freeze
      result = [test]
      class String
        def freeze = 5
      end
      result << test
    }, insns: [:opt_str_freeze], call_threshold: 1
  end

  def test_opt_str_freeze_rewritten
    assert_compiles "5", %q{
      class String
        def freeze = 5
      end
      def test = ''.freeze
      test
    }, insns: [:opt_str_freeze], call_threshold: 1
  end

  def test_opt_str_uminus
    assert_compiles "[\"\", 5]", %q{
      def test = -''
      result = [test]
      class String
        def -@ = 5
      end
      result << test
    }, insns: [:opt_str_uminus], call_threshold: 1
  end

  def test_opt_str_uminus_rewritten
    assert_compiles "5", %q{
      class String
        def -@ = 5
      end
      def test = -''
      test
    }, insns: [:opt_str_uminus], call_threshold: 1
  end

  def test_new_array_empty
    assert_compiles '[]', %q{
      def test = []
      test
    }, insns: [:newarray]
  end

  def test_new_array_nonempty
    assert_compiles '[5]', %q{
      def a = 5
      def test = [a]
      test
    }
  end

  def test_new_array_order
    assert_compiles '[3, 2, 1]', %q{
      def a = 3
      def b = 2
      def c = 1
      def test = [a, b, c]
      test
    }
  end

  def test_array_dup
    assert_compiles '[1, 2, 3]', %q{
      def test = [1,2,3]
      test
    }
  end

  def test_array_fixnum_aref
    assert_compiles '3', %q{
      def test(x) = [1,2,3][x]
      test(2)
      test(2)
    }, call_threshold: 2, insns: [:opt_aref]
  end

  def test_empty_array_pop
    assert_compiles 'nil', %q{
      def test(arr) = arr.pop
      test([])
      test([])
    }, call_threshold: 2
  end

  def test_array_pop_no_arg
    assert_compiles '42', %q{
      def test(arr) = arr.pop
      test([32, 33, 42])
      test([32, 33, 42])
    }, call_threshold: 2
  end

  def test_array_pop_arg
    assert_compiles '[33, 42]', %q{
      def test(arr) = arr.pop(2)
      test([32, 33, 42])
      test([32, 33, 42])
    }, call_threshold: 2
  end

  def test_new_range_inclusive
    assert_compiles '1..5', %q{
      def test(a, b) = a..b
      test(1, 5)
    }
  end

  def test_new_range_exclusive
    assert_compiles '1...5', %q{
      def test(a, b) = a...b
      test(1, 5)
    }
  end

  def test_new_range_with_literal
    assert_compiles '3..10', %q{
      def test(n) = n..10
      test(3)
    }
  end

  def test_new_range_fixnum_both_literals_inclusive
    assert_compiles '1..2', %q{
      def test()
        a = 2
        (1..a)
      end
      test; test
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_new_range_fixnum_both_literals_exclusive
    assert_compiles '1...2', %q{
      def test()
        a = 2
        (1...a)
      end
      test; test
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_new_range_fixnum_low_literal_inclusive
    assert_compiles '1..3', %q{
      def test(a)
        (1..a)
      end
      test(2); test(3)
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_new_range_fixnum_low_literal_exclusive
    assert_compiles '1...3', %q{
      def test(a)
        (1...a)
      end
      test(2); test(3)
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_new_range_fixnum_high_literal_inclusive
    assert_compiles '3..10', %q{
      def test(a)
        (a..10)
      end
      test(2); test(3)
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_new_range_fixnum_high_literal_exclusive
    assert_compiles '3...10', %q{
      def test(a)
        (a...10)
      end
      test(2); test(3)
    }, call_threshold: 2, insns: [:newrange]
  end

  def test_if
    assert_compiles '[0, nil]', %q{
      def test(n)
        if n < 5
          0
        end
      end
      [test(3), test(7)]
    }
  end

  def test_if_else
    assert_compiles '[0, 1]', %q{
      def test(n)
        if n < 5
          0
        else
          1
        end
      end
      [test(3), test(7)]
    }
  end

  def test_if_else_params
    assert_compiles '[1, 20]', %q{
      def test(n, a, b)
        if n < 5
          a
        else
          b
        end
      end
      [test(3, 1, 2), test(7, 10, 20)]
    }
  end

  def test_if_else_nested
    assert_compiles '[3, 8, 9, 14]', %q{
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
      [
        test(-1,  1,  2,  3,  4),
        test( 0,  5,  6,  7,  8),
        test( 3,  9, 10, 11, 12),
        test( 5, 13, 14, 15, 16),
      ]
    }
  end

  def test_if_else_chained
    assert_compiles '[12, 11, 21]', %q{
      def test(a)
        (if 2 < a then 1 else 2 end) + (if a < 4 then 10 else 20 end)
      end
      [test(0), test(3), test(5)]
    }
  end

  def test_if_elsif_else
    assert_compiles '[0, 2, 1]', %q{
      def test(n)
        if n < 5
          0
        elsif 8 < n
          1
        else
          2
        end
      end
      [test(3), test(7), test(9)]
    }
  end

  def test_ternary_operator
    assert_compiles '[1, 20]', %q{
      def test(n, a, b)
        n < 5 ? a : b
      end
      [test(3, 1, 2), test(7, 10, 20)]
    }
  end

  def test_ternary_operator_nested
    assert_compiles '[2, 21]', %q{
      def test(n, a, b)
        (n < 5 ? a : b) + 1
      end
      [test(3, 1, 2), test(7, 10, 20)]
    }
  end

  def test_while_loop
    assert_compiles '10', %q{
      def test(n)
        i = 0
        while i < n
          i = i + 1
        end
        i
      end
      test(10)
    }
  end

  def test_while_loop_chain
    assert_compiles '[135, 270]', %q{
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
      [test(5), test(10)]
    }
  end

  def test_while_loop_nested
    assert_compiles '[0, 4, 12]', %q{
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
      [test(0, 0), test(1, 3), test(10, 5)]
    }
  end

  def test_while_loop_if_else
    assert_compiles '[9, -1]', %q{
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
      [test(9), test(10)]
    }
  end

  def test_if_while_loop
    assert_compiles '[9, 12]', %q{
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
      [test(9), test(10)]
    }
  end

  def test_live_reg_past_ccall
    assert_compiles '2', %q{
      def callee = 1
      def test = callee + callee
      test
    }
  end

  def test_method_call
    assert_compiles '12', %q{
      def callee(a, b)
        a - b
      end

      def test
        callee(4, 2) + 10
      end

      test # profile test
      test
    }, call_threshold: 2
  end

  def test_recursive_fact
    assert_compiles '[1, 6, 720]', %q{
      def fact(n)
        if n == 0
          return 1
        end
        return n * fact(n-1)
      end
      [fact(0), fact(3), fact(6)]
    }
  end

  def test_profiled_fact
    assert_compiles '[1, 6, 720]', %q{
      def fact(n)
        if n == 0
          return 1
        end
        return n * fact(n-1)
      end
      fact(1) # profile fact
      [fact(0), fact(3), fact(6)]
    }, call_threshold: 3, num_profiles: 2
  end

  def test_recursive_fib
    assert_compiles '[0, 2, 3]', %q{
      def fib(n)
        if n < 2
          return n
        end
        return fib(n-1) + fib(n-2)
      end
      [fib(0), fib(3), fib(4)]
    }
  end

  def test_profiled_fib
    assert_compiles '[0, 2, 3]', %q{
      def fib(n)
        if n < 2
          return n
        end
        return fib(n-1) + fib(n-2)
      end
      fib(3) # profile fib
      [fib(0), fib(3), fib(4)]
    }, call_threshold: 5, num_profiles: 3
  end

  def test_spilled_basic_block_args
    assert_compiles '55', %q{
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
    }
  end

  def test_spilled_method_args
    assert_runs '55', %q{
      def foo(n1, n2, n3, n4, n5, n6, n7, n8, n9, n10)
        n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + n10
      end

      def test
        foo(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
      end

      test
    }

    # TODO(Shopify/ruby#716): Support spills and change to assert_compiles
    assert_runs '1', %q{
      def a(n1,n2,n3,n4,n5,n6,n7,n8,n9) = n1+n9
      a(2,0,0,0,0,0,0,0,-1)
    }

    # TODO(Shopify/ruby#716): Support spills and change to assert_compiles
    assert_runs '0', %q{
      def a(n1,n2,n3,n4,n5,n6,n7,n8) = n8
      a(1,1,1,1,1,1,1,0)
    }

    # TODO(Shopify/ruby#716): Support spills and change to assert_compiles
    # self param with spilled param
    assert_runs '"main"', %q{
      def a(n1,n2,n3,n4,n5,n6,n7,n8) = self
      a(1,0,0,0,0,0,0,0).to_s
    }
  end

  def test_spilled_param_new_arary
    # TODO(Shopify/ruby#716): Support spills and change to assert_compiles
    assert_runs '[:ok]', %q{
      def a(n1,n2,n3,n4,n5,n6,n7,n8) = [n8]
      a(0,0,0,0,0,0,0, :ok)
    }
  end

  def test_forty_param_method
    # This used to a trigger a miscomp on A64 due
    # to a memory displacement larger than 9 bits.
    # Using assert_runs again due to register spill.
    # TODO: It should be fixed by register spill support.
    assert_runs '1', %Q{
      def foo(#{'_,' * 39} n40) = n40

      foo(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1)
    }
  end

  def test_putself
    assert_compiles '3', %q{
      class Integer
        def minus(a)
          self - a
        end
      end
      5.minus(2)
    }
  end

  def test_getinstancevariable
    assert_compiles 'nil', %q{
      def test() = @foo

      test()
    }
    assert_compiles '3', %q{
      @foo = 3
      def test() = @foo

      test()
    }
  end

  def test_getinstancevariable_miss
    assert_compiles '[1, 1, 4]', %q{
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
    }
  end

  def test_setinstancevariable
    assert_compiles '1', %q{
      def test() = @foo = 1

      test()
      @foo
    }
  end

  def test_getclassvariable
    assert_compiles '42', %q{
      class Foo
        def self.test = @@x
      end

      Foo.class_variable_set(:@@x, 42)
      Foo.test()
    }
  end

  def test_getclassvariable_raises
    assert_compiles '"uninitialized class variable @@x in Foo"', %q{
      class Foo
        def self.test = @@x
      end

      begin
        Foo.test
      rescue NameError => e
        e.message
      end
    }
  end

  def test_setclassvariable
    assert_compiles '42', %q{
      class Foo
        def self.test = @@x = 42
      end

      Foo.test()
      Foo.class_variable_get(:@@x)
    }
  end

  def test_setclassvariable_raises
    assert_compiles '"can\'t modify frozen Class: Foo"', %q{
      class Foo
        def self.test = @@x = 42
        freeze
      end

      begin
        Foo.test
      rescue FrozenError => e
        e.message
      end
    }
  end

  def test_attr_reader
    assert_compiles '[4, 4]', %q{
      class C
        attr_reader :foo

        def initialize
          @foo = 4
        end
      end

      def test(c) = c.foo
      c = C.new
      [test(c), test(c)]
    }, call_threshold: 2, insns: [:opt_send_without_block]
  end

  def test_attr_accessor_getivar
    assert_compiles '[4, 4]', %q{
      class C
        attr_accessor :foo

        def initialize
          @foo = 4
        end
      end

      def test(c) = c.foo
      c = C.new
      [test(c), test(c)]
    }, call_threshold: 2, insns: [:opt_send_without_block]
  end

  def test_attr_accessor_setivar
    assert_compiles '[5, 5]', %q{
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

      c = C.new
      [test(c), test(c)]
    }, call_threshold: 2, insns: [:opt_send_without_block]
  end

  def test_attr_writer
    assert_compiles '[5, 5]', %q{
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
      c = C.new
      [test(c), test(c)]
    }, call_threshold: 2, insns: [:opt_send_without_block]
  end

  def test_uncached_getconstant_path
    assert_compiles RUBY_COPYRIGHT.dump, %q{
      def test = RUBY_COPYRIGHT
      test
    }, call_threshold: 1, insns: [:opt_getconstant_path]
  end

  def test_expandarray_no_splat
    assert_compiles '[3, 4]', %q{
      def test(o)
        a, b = o
        [a, b]
      end
      test [3, 4]
    }, call_threshold: 1, insns: [:expandarray]
  end

  def test_expandarray_splat
    assert_compiles '[3, [4]]', %q{
      def test(o)
        a, *b = o
        [a, b]
      end
      test [3, 4]
    }, call_threshold: 1, insns: [:expandarray]
  end

  def test_expandarray_splat_post
    assert_compiles '[3, [4], 5]', %q{
      def test(o)
        a, *b, c = o
        [a, b, c]
      end
      test [3, 4, 5]
    }, call_threshold: 1, insns: [:expandarray]
  end

  def test_getconstant_path_autoload
    # A constant-referencing expression can run arbitrary code through Kernel#autoload.
    Dir.mktmpdir('autoload') do |tmpdir|
      autoload_path = File.join(tmpdir, 'test_getconstant_path_autoload.rb')
      File.write(autoload_path, 'X = RUBY_COPYRIGHT')

      assert_compiles RUBY_COPYRIGHT.dump, %Q{
        Object.autoload(:X, #{File.realpath(autoload_path).inspect})
        def test = X
        test
      }, call_threshold: 1, insns: [:opt_getconstant_path]
    end
  end

  def test_constant_invalidation
    assert_compiles '123', <<~RUBY, call_threshold: 2, insns: [:opt_getconstant_path]
      class C; end
      def test = C
      test
      test

      C = 123
      test
    RUBY
  end

  def test_constant_path_invalidation
    assert_compiles '["Foo::C", "Foo::C", "Bar::C"]', <<~RUBY, call_threshold: 2, insns: [:opt_getconstant_path]
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
    RUBY
  end

  def test_single_ractor_mode_invalidation
    # Without invalidating the single-ractor mode, the test would crash
    assert_compiles '"errored but not crashed"', <<~RUBY, call_threshold: 2, insns: [:opt_getconstant_path]
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
    RUBY
  end

  def test_dupn
    assert_compiles '[[1], [1, 1], :rhs, [nil, :rhs]]', <<~RUBY, insns: [:dupn]
      def test(array) = (array[1, 2] ||= :rhs)

      one = [1, 1]
      start_empty = []
      [test(one), one, test(start_empty), start_empty]
    RUBY
  end

  def test_send_backtrace
    backtrace = [
      "-e:2:in 'Object#jit_frame1'",
      "-e:3:in 'Object#entry'",
      "-e:5:in 'block in <main>'",
      "-e:6:in '<main>'",
    ]
    assert_compiles backtrace.inspect, %q{
      def jit_frame2 = caller     # 1
      def jit_frame1 = jit_frame2 # 2
      def entry = jit_frame1      # 3
      entry # profile send        # 4
      entry                       # 5
    }, call_threshold: 2
  end

  def test_bop_invalidation
    assert_compiles '100', %q{
      def test
        eval(<<~RUBY)
          class Integer
            def +(_) = 100
          end
        RUBY
        1 + 2
      end
      test
    }
  end

  def test_defined_with_defined_values
    assert_compiles '["constant", "method", "global-variable"]', %q{
      class Foo; end
      def bar; end
      $ruby = 1

      def test = return defined?(Foo), defined?(bar), defined?($ruby)

      test
    }, insns: [:defined]
  end

  def test_defined_with_undefined_values
    assert_compiles '[nil, nil, nil]', %q{
      def test = return defined?(Foo), defined?(bar), defined?($ruby)

      test
    }, insns: [:defined]
  end

  def test_defined_with_method_call
    assert_compiles '["method", nil]', %q{
      def test = return defined?("x".reverse(1)), defined?("x".reverse(1).reverse)

      test
    }, insns: [:defined]
  end

  def test_defined_method_raise
    assert_compiles '[nil, nil, nil]', %q{
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
    }
  end

  def test_defined_yield
    assert_compiles "nil", "defined?(yield)"
    assert_compiles '[nil, nil, "yield"]', %q{
      def test = defined?(yield)
      [test, test, test{}]
    }, call_threshold: 2, insns: [:defined]
  end

  def test_defined_yield_from_block
    # This will do some EP hopping to find the local EP,
    # so it's slightly different than doing it outside of a block.

    assert_compiles '[nil, nil, "yield"]', %q{
      def test
        yield_self { yield_self { defined?(yield) } }
      end

      [test, test, test{}]
    }, call_threshold: 2
  end

  def test_block_given_p
    assert_compiles "false", "block_given?"
    assert_compiles '[false, false, true]', %q{
      def test = block_given?
      [test, test, test{}]
    }, call_threshold: 2, insns: [:opt_send_without_block]
  end

  def test_block_given_p_from_block
    # This will do some EP hopping to find the local EP,
    # so it's slightly different than doing it outside of a block.

    assert_compiles '[false, false, true]', %q{
      def test
        yield_self { yield_self { block_given? } }
      end

      [test, test, test{}]
    }, call_threshold: 2
  end

  def test_invokeblock_without_block_after_jit_call
    assert_compiles '"no block given (yield)"', %q{
      def test(*arr, &b)
        arr.class
        yield
      end
      begin
        test
      rescue => e
        e.message
      end
    }
  end

  def test_putspecialobject_vm_core_and_cbase
    assert_compiles '10', %q{
      def test
        alias bar test
        10
      end

      test
      bar
    }, insns: [:putspecialobject]
  end

  def test_putspecialobject_const_base
    assert_compiles '1', %q{
      Foo = 1

      def test = Foo

      # First call: populates the constant cache
      test
      # Second call: triggers ZJIT compilation with warm cache
      # RubyVM::ZJIT.assert_compiles will panic if this fails to compile
      test
    }, call_threshold: 2
  end

  def test_branchnil
    assert_compiles '[2, nil]', %q{
      def test(x)
        x&.succ
      end
      [test(1), test(nil)]
    }, call_threshold: 1, insns: [:branchnil]
  end

  def test_nil_nil
    assert_compiles 'true', %q{
      def test = nil.nil?
      test
    }, insns: [:opt_nil_p]
  end

  def test_non_nil_nil
    assert_compiles 'false', %q{
      def test = 1.nil?
      test
    }, insns: [:opt_nil_p]
  end

  def test_getspecial_last_match
    assert_compiles '"hello"', %q{
      def test(str)
        str =~ /hello/
        $&
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_match_pre
    assert_compiles '"hello "', %q{
      def test(str)
        str =~ /world/
        $`
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_match_post
    assert_compiles '" world"', %q{
      def test(str)
        str =~ /hello/
        $'
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_match_last_group
    assert_compiles '"world"', %q{
      def test(str)
        str =~ /(hello) (world)/
        $+
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_numbered_match_1
    assert_compiles '"hello"', %q{
      def test(str)
        str =~ /(hello) (world)/
        $1
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_numbered_match_2
    assert_compiles '"world"', %q{
      def test(str)
        str =~ /(hello) (world)/
        $2
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_numbered_match_nonexistent
    assert_compiles 'nil', %q{
      def test(str)
        str =~ /(hello)/
        $2
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_no_match
    assert_compiles 'nil', %q{
      def test(str)
        str =~ /xyz/
        $&
      end
      test("hello world")
    }, insns: [:getspecial]
  end

  def test_getspecial_complex_pattern
    assert_compiles '"123"', %q{
      def test(str)
        str =~ /(\d+)/
        $1
      end
      test("abc123def")
    }, insns: [:getspecial]
  end

  def test_getspecial_multiple_groups
    assert_compiles '"456"', %q{
      def test(str)
        str =~ /(\d+)-(\d+)/
        $2
      end
      test("123-456")
    }, insns: [:getspecial]
  end

  # tool/ruby_vm/views/*.erb relies on the zjit instructions a) being contiguous and
  # b) being reliably ordered after all the other instructions.
  def test_instruction_order
    insn_names = RubyVM::INSTRUCTION_NAMES
    zjit, others = insn_names.map.with_index.partition { |name, _| name.start_with?('zjit_') }
    zjit_indexes = zjit.map(&:last)
    other_indexes = others.map(&:last)
    zjit_indexes.product(other_indexes).each do |zjit_index, other_index|
      assert zjit_index > other_index, "'#{insn_names[zjit_index]}' at #{zjit_index} "\
        "must be defined after '#{insn_names[other_index]}' at #{other_index}"
    end
  end

  def test_require_rubygems
    assert_runs 'true', %q{
      require 'rubygems'
    }, call_threshold: 2
  end

  def test_require_rubygems_with_auto_compact
    omit("GC.auto_compact= support is required for this test") unless GC.respond_to?(:auto_compact=)
    assert_runs 'true', %q{
      GC.auto_compact = true
      require 'rubygems'
    }, call_threshold: 2
  end

  def test_stats_availability
    assert_runs '[true, true]', %q{
      def test = 1
      test
      [
        RubyVM::ZJIT.stats[:zjit_insn_count] > 0,
        RubyVM::ZJIT.stats(:zjit_insn_count) > 0,
      ]
    }, stats: true
  end

  def test_stats_consistency
    assert_runs '[]', %q{
      def test = 1
      test # increment some counters

      RubyVM::ZJIT.stats.to_a.filter_map do |key, value|
        # The value may be incremented, but the class should stay the same
        other_value = RubyVM::ZJIT.stats(key)
        if value.class != other_value.class
          [key, value, other_value]
        end
      end
    }, stats: true
  end

  def test_reset_stats
    assert_runs 'true', %q{
      def test = 1
      100.times { test }

      # Get initial stats and verify they're non-zero
      initial_stats = RubyVM::ZJIT.stats

      # Reset the stats
      RubyVM::ZJIT.reset_stats!

      # Get stats after reset
      reset_stats = RubyVM::ZJIT.stats

      [
        # After reset, counters should be zero or at least much smaller
        # (some instructions might execute between reset and reading stats)
        :zjit_insn_count.then { |s| initial_stats[s] > 0 && reset_stats[s] < initial_stats[s] },
        :compiled_iseq_count.then { |s| initial_stats[s] > 0 && reset_stats[s] < initial_stats[s] }
      ].all?
    }, stats: true
  end

  def test_zjit_option_uses_array_each_in_ruby
    omit 'ZJIT wrongly compiles Array#each, so it is disabled for now'
    assert_runs '"<internal:array>"', %q{
      Array.instance_method(:each).source_location&.first
    }
  end

  def test_profile_under_nested_jit_call
    assert_compiles '[nil, nil, 3]', %q{
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
    }, call_threshold: 2
  end

  def test_bop_redefined
    assert_runs '[3, :+, 100]', %q{
      def test
        1 + 2
      end

      test # profile opt_plus
      [test, Integer.class_eval { def +(_) = 100 }, test]
    }, call_threshold: 2
  end

  def test_bop_redefined_with_adjacent_patch_points
    assert_runs '[15, :+, 100]', %q{
      def test
        1 + 2 + 3 + 4 + 5
      end

      test # profile opt_plus
      [test, Integer.class_eval { def +(_) = 100 }, test]
    }, call_threshold: 2
  end

  # ZJIT currently only generates a MethodRedefined patch point when the method
  # is called on the top-level self.
  def test_method_redefined_with_top_self
    assert_runs '["original", "redefined"]', %q{
      def foo
        "original"
      end

      def test = foo

      test; test

      result1 = test

      # Redefine the method
      def foo
        "redefined"
      end

      result2 = test

      [result1, result2]
    }, call_threshold: 2
  end

  def test_method_redefined_with_module
    assert_runs '["original", "redefined"]', %q{
      module Foo
        def self.foo = "original"
      end

      def test = Foo.foo
      test
      result1 = test

      def Foo.foo = "redefined"
      result2 = test

      [result1, result2]
    }, call_threshold: 2
  end

  def test_module_name_with_guard_passes
    assert_compiles '"Integer"', %q{
      def test(mod)
        mod.name
      end

      test(String)
      test(Integer)
    }, call_threshold: 2
  end

  def test_module_name_with_guard_side_exit
    # This test demonstrates that the guard side exit works correctly
    # In this case, when we call with a non-Class object, it should fall back to interpreter
    assert_compiles '["String", "Integer", "Bar"]', %q{
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
    }, call_threshold: 2
  end

  def test_objtostring_calls_to_s_on_non_strings
    assert_compiles '["foo", "foo"]', %q{
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
    }
  end

  def test_objtostring_rewrite_does_not_call_to_s_on_strings
    assert_compiles '["foo", "foo"]', %q{
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
    }
  end

  def test_objtostring_rewrite_does_not_call_to_s_on_string_subclasses
    assert_compiles '["foo", "foo"]', %q{
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
    }
  end

  def test_objtostring_profiled_string_fastpath
    assert_compiles '"foo"', %q{
      def test(str)
        "#{str}"
      end
      test('foo'); test('foo') # profile as string
    }, call_threshold: 2
  end

  def test_objtostring_profiled_string_subclass_fastpath
    assert_compiles '"foo"', %q{
      class MyString < String; end

      def test(str)
        "#{str}"
      end

      foo = MyString.new("foo")
      test(foo); test(foo) # still profiles as string
    }, call_threshold: 2
  end

  def test_objtostring_profiled_string_fastpath_exits_on_nonstring
    assert_compiles '"1"', %q{
      def test(str)
        "#{str}"
      end

      test('foo') # profile as string
      test(1)
    }, call_threshold: 2
  end

  def test_objtostring_profiled_nonstring_calls_to_s
    assert_compiles '"[1, 2, 3]"', %q{
      def test(str)
        "#{str}"
      end

      test([1,2,3]); # profile as nonstring
      test([1,2,3]);
    }, call_threshold: 2
  end

  def test_objtostring_profiled_nonstring_guard_exits_when_string
    assert_compiles '"foo"', %q{
      def test(str)
        "#{str}"
      end

      test([1,2,3]); # profiles as nonstring
      test('foo');
    }, call_threshold: 2
  end

  def test_string_bytesize_with_guard
    assert_compiles '5', %q{
      def test(str)
        str.bytesize
      end

      test('hello')
      test('world')
    }, call_threshold: 2
  end

  def test_string_bytesize_multibyte
    assert_compiles '4', %q{
      def test(s)
        s.bytesize
      end

      test("💎")
    }, call_threshold: 2
  end

  def test_nil_value_nil_opt_with_guard
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(nil)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_nil_value_nil_opt_with_guard_side_exit
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(nil)
      test(nil)
      test(1)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_true_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(true)
      test(true)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_true_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(true)
      test(true)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_false_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(false)
      test(false)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_false_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(false)
      test(false)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_integer_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(1)
      test(2)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_integer_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(1)
      test(2)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_float_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(1.0)
      test(2.0)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_float_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(1.0)
      test(2.0)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_symbol_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(:foo)
      test(:bar)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_symbol_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(:foo)
      test(:bar)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_class_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(String)
      test(Integer)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_class_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(String)
      test(Integer)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_module_nil_opt_with_guard
    assert_compiles 'false', %q{
      def test(val) = val.nil?

      test(Enumerable)
      test(Kernel)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_module_nil_opt_with_guard_side_exit
    assert_compiles 'true', %q{
      def test(val) = val.nil?

      test(Enumerable)
      test(Kernel)
      test(nil)
    }, call_threshold: 2, insns: [:opt_nil_p]
  end

  def test_basic_object_guard_works_with_immediate
    assert_compiles 'NilClass', %q{
      class Foo; end

      def test(val) = val.class

      test(Foo.new)
      test(Foo.new)
      test(nil)
    }, call_threshold: 2
  end

  def test_basic_object_guard_works_with_false
    assert_compiles 'FalseClass', %q{
      class Foo; end

      def test(val) = val.class

      test(Foo.new)
      test(Foo.new)
      test(false)
    }, call_threshold: 2
  end

  def test_string_concat
    assert_compiles '"123"', %q{
      def test = "#{1}#{2}#{3}"

      test
    }, insns: [:concatstrings]
  end

  def test_string_concat_empty
    assert_compiles '""', %q{
      def test = "#{}"

      test
    }, insns: [:concatstrings]
  end

  def test_regexp_interpolation
    assert_compiles '/123/', %q{
      def test = /#{1}#{2}#{3}/

      test
    }, insns: [:toregexp]
  end

  def test_new_range_non_leaf
    assert_compiles '(0/1)..1', %q{
      def jit_entry(v) = make_range_then_exit(v)

      def make_range_then_exit(v)
        range = (v..1)
        super rescue range # TODO(alan): replace super with side-exit intrinsic
      end

      jit_entry(0)    # profile
      jit_entry(0)    # compile
      jit_entry(0/1r) # run without stub
    }, call_threshold: 2
  end

  def test_raise_in_second_argument
    assert_compiles '{ok: true}', %q{
      def write(hash, key)
        hash[key] = raise rescue true
        hash
      end

      write({}, :ok)
    }
  end

  def test_ivar_attr_reader_optimization_with_multi_ractor_mode
    assert_compiles '42', %q{
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

      Foo.bar = [] # needs to be a ractor unshareable object

      def test
        Foo.get_bar
      end

      test
      test

      Ractor.new { test }.value
    }, call_threshold: 2
  end

  def test_ivar_get_with_multi_ractor_mode
    assert_compiles '42', %q{
      class Foo
        def self.set_bar
          @bar = [] # needs to be a ractor unshareable object
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
    }, call_threshold: 2
  end

  def test_ivar_get_with_already_multi_ractor_mode
    assert_compiles '42', %q{
      class Foo
        def self.set_bar
          @bar = [] # needs to be a ractor unshareable object
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
    }, call_threshold: 2
  end

  def test_ivar_set_with_multi_ractor_mode
    assert_compiles '42', %q{
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
    }
  end

  def test_struct_set
    assert_compiles '[42, 42, :frozen_error]', %q{
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
    }, call_threshold: 2
  end

  def test_global_tracepoint
    assert_compiles 'true', %q{
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
    }
  end

  def test_local_tracepoint
    assert_compiles 'true', %q{
      def foo = 1

      foo
      foo

      called = false

      tp = TracePoint.new(:return) { |_| called = true }
      tp.enable(target: method(:foo)) do
        foo
      end
      called
    }
  end

  def test_line_tracepoint_on_c_method
    assert_compiles '"[[:line, true]]"', %q{
      events = []
      events.instance_variable_set(
        :@tp,
        TracePoint.new(:line) { |tp| events << [tp.event, tp.lineno] if tp.path == __FILE__ }
      )
      def events.to_str
        @tp.enable; ''
      end

      # Stay in generated code while enabling tracing
      def events.compiled(obj)
        String(obj)
        @tp.disable; __LINE__
      end

      line = events.compiled(events)
      events[0][-1] = (events[0][-1] == line)

      events.to_s # can't dump events as it's a singleton object AND it has a TracePoint instance variable, which also can't be dumped
    }
  end

  def test_targeted_line_tracepoint_in_c_method_call
    assert_compiles '"[true]"', %q{
      events = []
      events.instance_variable_set(:@tp, TracePoint.new(:line) { |tp| events << tp.lineno })
      def events.to_str
        @tp.enable(target: method(:compiled))
        ''
      end

      # Stay in generated code while enabling tracing
      def events.compiled(obj)
        String(obj)
        __LINE__
      end

      line = events.compiled(events)
      events[0] = (events[0] == line)

      events.to_s # can't dump events as it's a singleton object AND it has a TracePoint instance variable, which also can't be dumped
    }
  end

  def test_opt_case_dispatch
    assert_compiles '[true, false]', %q{
      def test(x)
        case x
        when :foo
          true
        else
          false
        end
      end

      results = []
      results << test(:foo)
      results << test(1)
      results
    }, insns: [:opt_case_dispatch]
  end

  def test_stack_overflow
    assert_compiles 'nil', %q{
      def recurse(n)
        return if n == 0
        recurse(n-1)
        nil # no tail call
      end

      recurse(2)
      recurse(2)
      begin
        recurse(20_000)
      rescue SystemStackError
        # Not asserting an exception is raised here since main
        # thread stack size is environment-sensitive. Only
        # that we don't crash or infinite loop.
      end
    }, call_threshold: 2
  end

  def test_invokeblock
    assert_compiles '42', %q{
      def test
        yield
      end
      test { 42 }
    }, insns: [:invokeblock]
  end

  def test_invokeblock_with_args
    assert_compiles '3', %q{
      def test(x, y)
        yield x, y
      end
      test(1, 2) { |a, b| a + b }
    }, insns: [:invokeblock]
  end

  def test_invokeblock_no_block_given
    assert_compiles ':error', %q{
      def test
        yield rescue :error
      end
      test
    }, insns: [:invokeblock]
  end

  def test_invokeblock_multiple_yields
    assert_compiles "[1, 2, 3]", %q{
      results = []
      def test
        yield 1
        yield 2
        yield 3
      end
      test { |x| results << x }
      results
    }, insns: [:invokeblock]
  end

  def test_ccall_variadic_with_multiple_args
    assert_compiles "[1, 2, 3]", %q{
      def test
        a = []
        a.push(1, 2, 3)
        a
      end

      test
      test
    }, insns: [:opt_send_without_block]
  end

  def test_ccall_variadic_with_no_args
    assert_compiles "[1]", %q{
      def test
        a = [1]
        a.push
      end

      test
      test
    }, insns: [:opt_send_without_block]
  end

  def test_ccall_variadic_with_no_args_causing_argument_error
    assert_compiles ":error", %q{
      def test
        format
      rescue ArgumentError
        :error
      end

      test
      test
    }, insns: [:opt_send_without_block]
  end

  def test_allocating_in_hir_c_method_is
    assert_compiles ":k", %q{
      # Put opt_new in a frame JIT code sets up that doesn't set cfp->pc
      def a(f) = test(f)
      def test(f) = (f.new if f)
      # A parallel couple methods that will set PC at the same stack height
      def second = third
      def third = nil

      a(nil)
      a(nil)

      class Foo
        def self.new = :k
      end

      second

      a(Foo)
    }, call_threshold: 2, insns: [:opt_new]
  end

  def test_singleton_class_invalidation_annotated_ccall
    assert_compiles '[false, true]', %q{
      def define_singleton(obj, define)
        if define
          # Wrap in C method frame to avoid exiting JIT on defineclass
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
        # This == call gets compiled to a CCall
        obj == define_singleton(obj, define)
      end

      result = []
      result << test(false)  # Compiles BasicObject#==
      result << test(true)   # Should use singleton#== now
      result
    }, call_threshold: 2
  end

  def test_singleton_class_invalidation_optimized_variadic_ccall
    assert_compiles '[1, 1000]', %q{
      def define_singleton(arr, define)
        if define
          # Wrap in C method frame to avoid exiting JIT on defineclass
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
        arr.push(val)  # This CCall should be invalidated if singleton was defined
        arr[0]
      end

      result = []
      result << test(false)  # Compiles Array#push as CCall
      result << test(true)   # Singleton defined, CCall should be invalidated
      result
    }, call_threshold: 2
  end

  def test_regression_cfp_sp_set_correctly_before_leaf_gc_call
    assert_compiles ':ok', %q{
      def check(l, r)
        return 1 unless l
        1 + check(*l) + check(*r)
      end

      def tree(depth)
        # This duparray is our leaf-gc target.
        return [nil, nil] unless depth > 0

        # Modify the local and pass it to the following calls.
        depth -= 1
        [tree(depth), tree(depth)]
      end

      def test
        GC.stress = true
        2.times do
          t = tree(11)
          check(*t)
        end
        :ok
      end

      test
    }, call_threshold: 14, num_profiles: 5
  end

  private

  # Assert that every method call in `test_script` can be compiled by ZJIT
  # at a given call_threshold
  def assert_compiles(expected, test_script, insns: [], **opts)
    assert_runs(expected, test_script, insns:, assert_compiles: true, **opts)
  end

  # Assert that `test_script` runs successfully with ZJIT enabled.
  # Unlike `assert_compiles`, `assert_runs(assert_compiles: false)`
  # allows ZJIT to skip compiling methods.
  def assert_runs(expected, test_script, insns: [], assert_compiles: false, **opts)
    pipe_fd = 3
    disasm_method = :test

    script = <<~RUBY
      ret_val = (_test_proc = -> { #{('RubyVM::ZJIT.assert_compiles; ' if assert_compiles)}#{test_script.lstrip} }).call
      result = {
        ret_val:,
        #{ unless insns.empty?
           "insns: RubyVM::InstructionSequence.of(method(#{disasm_method.inspect})).to_a"
        end}
      }
      IO.open(#{pipe_fd}).write(Marshal.dump(result))
    RUBY

    out, err, status, result = eval_with_jit(script, pipe_fd:, **opts)
    assert_success(out, err, status)

    result = Marshal.load(result)
    assert_equal(expected, result.fetch(:ret_val).inspect)

    unless insns.empty?
      iseq = result.fetch(:insns)
      assert_equal(
        "YARVInstructionSequence/SimpleDataFormat",
        iseq.first,
        "Failed to get ISEQ disassembly. " \
        "Make sure to put code directly under the '#{disasm_method}' method."
      )
      iseq_insns = iseq.last

      expected_insns = Set.new(insns)
      iseq_insns.each do
        next unless it.is_a?(Array)
        expected_insns.delete(it.first)
      end
      assert(expected_insns.empty?, -> { "Not present in ISeq: #{expected_insns.to_a}" })
    end
  end

  # Run a Ruby process with ZJIT options and a pipe for writing test results
  def eval_with_jit(
    script,
    call_threshold: 1,
    num_profiles: 1,
    zjit: true,
    stats: false,
    debug: true,
    allowed_iseqs: nil,
    timeout: 1000,
    pipe_fd: nil
  )
    args = ["--disable-gems"]
    if zjit
      args << "--zjit-call-threshold=#{call_threshold}"
      args << "--zjit-num-profiles=#{num_profiles}"
      case stats
      when true
        args << "--zjit-stats"
      when :quiet
        args << "--zjit-stats-quiet"
      else
        args << "--zjit-stats=#{stats}" if stats
      end
      args << "--zjit-debug" if debug
      if allowed_iseqs
        jitlist = Tempfile.new("jitlist")
        jitlist.write(allowed_iseqs)
        jitlist.close
        args << "--zjit-allowed-iseqs=#{jitlist.path}"
      end
    end
    args << "-e" << script_shell_encode(script)
    ios = {}
    if pipe_fd
      pipe_r, pipe_w = IO.pipe
      # Separate thread so we don't deadlock when
      # the child ruby blocks writing the output to pipe_fd
      pipe_out = nil
      pipe_reader = Thread.new do
        pipe_out = pipe_r.read
        pipe_r.close
      end
      ios[pipe_fd] = pipe_w
    end
    result = EnvUtil.invoke_ruby(args, '', true, true, rubybin: RbConfig.ruby, timeout: timeout, ios:)
    if pipe_fd
      pipe_w.close
      pipe_reader.join(timeout)
      result << pipe_out
    end
    result
  ensure
    pipe_reader&.kill
    pipe_reader&.join(timeout)
    pipe_r&.close
    pipe_w&.close
    jitlist&.unlink
  end

  def assert_success(out, err, status)
    message = "exited with status #{status.to_i}"
    message << "\nstdout:\n```\n#{out}```\n" unless out.empty?
    message << "\nstderr:\n```\n#{err}```\n" unless err.empty?
    assert status.success?, message
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end
end
