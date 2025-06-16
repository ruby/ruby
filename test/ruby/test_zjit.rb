# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS=test/ruby/test_zjit.rb

require 'test/unit'
require 'envutil'
require_relative '../lib/jit_support'
return unless JITSupport.zjit_supported?

class TestZJIT < Test::Unit::TestCase
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

  def test_setlocal
    assert_compiles '3', %q{
      def test(n)
        m = n
        m
      end
      test(3)
    }
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

  def test_opt_aref_with
    assert_compiles ':ok', %q{
      def aref_with(hash) = hash["key"]

      aref_with({ "key" => :ok })
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

  def test_setinstancevariable
    assert_compiles '1', %q{
      def test() = @foo = 1

      test()
      @foo
    }
  end

  def test_uncached_getconstant_path
    assert_compiles RUBY_COPYRIGHT.dump, %q{
      def test = RUBY_COPYRIGHT
      test
    }, call_threshold: 1, insns: [:opt_getconstant_path]
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

  private

  # Assert that every method call in `test_script` can be compiled by ZJIT
  # at a given call_threshold
  def assert_compiles(expected, test_script, insns: [], **opts)
    pipe_fd = 3

    script = <<~RUBY
      ret_val = (_test_proc = -> { RubyVM::ZJIT.assert_compiles; #{test_script.lstrip} }).call
      result = {
        ret_val:,
        #{ unless insns.empty?
          'insns: RubyVM::InstructionSequence.of(_test_proc).enum_for(:each_child).map(&:to_a)'
        end}
      }
      IO.open(#{pipe_fd}).write(Marshal.dump(result))
    RUBY

    status, out, err, result = eval_with_jit(script, pipe_fd:, **opts)

    message = "exited with status #{status.to_i}"
    message << "\nstdout:\n```\n#{out}```\n" unless out.empty?
    message << "\nstderr:\n```\n#{err}```\n" unless err.empty?
    assert status.success?, message

    result = Marshal.load(result)
    assert_equal expected, result.fetch(:ret_val).inspect

    unless insns.empty?
      iseqs = result.fetch(:insns)
      iseqs.filter! { it[9] == :method } # ISeq type
      assert_equal 1, iseqs.size, "Opcode assertions tests must define exactly one method"
      iseq_insns = iseqs.first.last

      expected_insns = Set.new(insns)
      iseq_insns.each do
        next unless it.is_a?(Array)
        expected_insns.delete(it.first)
      end
      assert(expected_insns.empty?, -> { "Not present in ISeq: #{expected_insns.to_a}" })
    end
  end

  # Run a Ruby process with ZJIT options and a pipe for writing test results
  def eval_with_jit(script, call_threshold: 1, num_profiles: 1, timeout: 1000, pipe_fd:, debug: true)
    args = [
      "--disable-gems",
      "--zjit-call-threshold=#{call_threshold}",
      "--zjit-num-profiles=#{num_profiles}",
    ]
    args << "--zjit-debug" if debug
    args << "-e" << script_shell_encode(script)
    pipe_r, pipe_w = IO.pipe
    # Separate thread so we don't deadlock when
    # the child ruby blocks writing the output to pipe_fd
    pipe_out = nil
    pipe_reader = Thread.new do
      pipe_out = pipe_r.read
      pipe_r.close
    end
    out, err, status = EnvUtil.invoke_ruby(args, '', true, true, rubybin: RbConfig.ruby, timeout: timeout, ios: { pipe_fd => pipe_w })
    pipe_w.close
    pipe_reader.join(timeout)
    [status, out, err, pipe_out]
  ensure
    pipe_reader&.kill
    pipe_reader&.join(timeout)
    pipe_r&.close
    pipe_w&.close
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end
end
