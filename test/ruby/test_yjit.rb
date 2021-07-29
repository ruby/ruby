# frozen_string_literal: true
require 'test/unit'
require 'envutil'
require 'tmpdir'

return unless YJIT.enabled?

# Tests for YJIT with assertions on compilation and side exits
# insipired by the MJIT tests in test/ruby/test_jit.rb
class TestYJIT < Test::Unit::TestCase
  def test_compile_putnil
    assert_compiles('nil', insns: %i[putnil], result: nil)
  end

  def test_compile_putobject
    assert_compiles('true', insns: %i[putobject], result: true)
    assert_compiles('123', insns: %i[putobject], result: 123)
    assert_compiles(':foo', insns: %i[putobject], result: :foo)
  end

  def test_compile_opt_not
    assert_compiles('!false', insns: %i[opt_not], result: true)
    assert_compiles('!nil', insns: %i[opt_not], result: true)
    assert_compiles('!true', insns: %i[opt_not], result: false)
    assert_compiles('![]', insns: %i[opt_not], result: false)
  end

  def test_compile_opt_newarray
    assert_compiles('[]', insns: %i[newarray], result: [])
    assert_compiles('[1+1]', insns: %i[newarray opt_plus], result: [2])
    assert_compiles('[1,1+1,3,4,5,6]', insns: %i[newarray opt_plus], result: [1, 2, 3, 4, 5, 6])
  end

  def test_compile_opt_duparray
    assert_compiles('[1]', insns: %i[duparray], result: [1])
    assert_compiles('[1, 2, 3]', insns: %i[duparray], result: [1, 2, 3])
  end

  def test_compile_opt_nil_p
    assert_compiles('nil.nil?', insns: %i[opt_nil_p], result: true)
    assert_compiles('false.nil?', insns: %i[opt_nil_p], result: false)
    assert_compiles('true.nil?', insns: %i[opt_nil_p], result: false)
    assert_compiles('(-"").nil?', insns: %i[opt_nil_p], result: false)
    assert_compiles('123.nil?', insns: %i[opt_nil_p], result: false)
  end

  def test_compile_eq_fixnum
    assert_compiles('123 == 123', insns: %i[opt_eq], result: true)
    assert_compiles('123 == 456', insns: %i[opt_eq], result: false)
  end

  def test_compile_eq_string
    assert_compiles('-"" == -""', insns: %i[opt_eq], result: true)
    assert_compiles('-"foo" == -"foo"', insns: %i[opt_eq], result: true)
    assert_compiles('-"foo" == -"bar"', insns: %i[opt_eq], result: false)
  end

  def test_compile_set_and_get_global
    assert_compiles('$foo = 123; $foo', insns: %i[setglobal], result: 123)
  end

  def test_getlocal_with_level
    assert_compiles(<<~RUBY, insns: %i[getlocal opt_plus], result: [[7]])
      def foo(foo, bar)
        [1].map do |x|
          [1].map do |y|
            foo + bar
          end
        end
      end

      foo(5, 2)
    RUBY
  end

  def test_string_then_nil
    assert_compiles(<<~RUBY, insns: %i[opt_nil_p], result: true)
      def foo(val)
        val.nil?
      end

      foo("foo")
      foo(nil)
    RUBY
  end

  def test_nil_then_string
    assert_compiles(<<~RUBY, insns: %i[opt_nil_p], result: false)
      def foo(val)
        val.nil?
      end

      foo(nil)
      foo("foo")
    RUBY
  end

  def test_opt_length_in_method
    assert_compiles(<<~RUBY, insns: %i[opt_length], result: 5)
      def foo(str)
        str.length
      end

      foo("hello, ")
      foo("world")
    RUBY
  end

  def test_compile_opt_getinlinecache
    assert_compiles(<<~RUBY, insns: %i[opt_getinlinecache], result: 123, min_calls: 2)
      def get_foo
        FOO
      end

      FOO = 123

      get_foo # warm inline cache
      get_foo
    RUBY
  end

  def test_string_interpolation
    assert_compiles(<<~'RUBY', insns: %i[checktype concatstrings], result: "foobar", min_calls: 2)
      def make_str(foo, bar)
        "#{foo}#{bar}"
      end

      make_str("foo", "bar")
      make_str("foo", "bar")
    RUBY
  end

  def test_fib_recursion
    assert_compiles(<<~'RUBY', insns: %i[opt_le opt_minus opt_plus opt_send_without_block], result: 34)
      def fib(n)
        return n if n <= 1
        fib(n-1) + fib(n-2)
      end

      fib(9)
    RUBY
  end

  def test_ctx_different_mappings
    # regression test simplified from URI::Generic#hostname=
    assert_compiles(<<~'RUBY', frozen_string_literal: true)
      def foo(v)
        !(v&.start_with?('[')) && v&.index(':')
      end

      foo(nil)
      foo("example.com")
    RUBY
  end

  def assert_no_exits(script)
    assert_compiles(script)
  end

  ANY = Object.new
  def assert_compiles(test_script, insns: [], min_calls: 1, stdout: nil, exits: {}, result: ANY, frozen_string_literal: nil)
    reset_stats = <<~RUBY
      YJIT.runtime_stats
      YJIT.reset_stats!
    RUBY

    write_results = <<~RUBY
      stats = YJIT.runtime_stats

      def collect_blocks(blocks)
        blocks.sort_by(&:address).map { |b| [b.iseq_start_index, b.iseq_end_index] }
      end

      def collect_iseqs(iseq)
        iseq_array = iseq.to_a
        insns = iseq_array.last.grep(Array)
        blocks = YJIT.blocks_for(iseq)
        h = {
          name: iseq_array[5],
          insns: insns,
          blocks: collect_blocks(blocks),
        }
        arr = [h]
        iseq.each_child { |c| arr.concat collect_iseqs(c) }
        arr
      end

      iseq = RubyVM::InstructionSequence.of(_test_proc)
      IO.open(3).write Marshal.dump({
        result: result,
        stats: stats,
        iseqs: collect_iseqs(iseq),
        disasm: iseq.disasm
      })
    RUBY

    script = <<~RUBY
      #{"# frozen_string_literal: true" if frozen_string_literal}
      _test_proc = proc {
        #{test_script}
      }
      #{reset_stats}
      result = _test_proc.call
      #{write_results}
    RUBY

    status, out, err, stats = eval_with_jit(script, min_calls: min_calls)

    assert status.success?, "exited with status #{status.to_i}, stderr:\n#{err}"

    assert_equal stdout.chomp, out.chomp if stdout

    unless ANY.equal?(result)
      assert_equal result, stats[:result]
    end

    runtime_stats = stats[:stats]
    iseqs = stats[:iseqs]
    disasm = stats[:disasm]

    # Only available when RUBY_DEBUG enabled
    if runtime_stats[:all_stats]
      recorded_exits = runtime_stats.select { |k, v| k.to_s.start_with?("exit_") }
      recorded_exits = recorded_exits.reject { |k, v| v == 0 }

      recorded_exits.transform_keys! { |k| k.to_s.gsub("exit_", "").to_sym }
      if exits != :any && exits != recorded_exits
        flunk "Expected #{exits.empty? ? "no" : exits.inspect} exits" \
          ", but got\n#{recorded_exits.inspect}"
      end
    end

    # Only available when RUBY_DEBUG enabled
    if runtime_stats[:all_stats]
      missed_insns = insns.dup
      all_compiled_blocks = {}
      iseqs.each do |iseq|
        compiled_blocks = iseq[:blocks].map { |from, to| (from...to) }
        all_compiled_blocks[iseq[:name]] = compiled_blocks
        compiled_insns = iseq[:insns]
        next_idx = 0
        compiled_insns.map! do |insn|
          # TODO: not sure this is accurate for determining insn size
          idx = next_idx
          next_idx += insn.length
          [idx, *insn]
        end

        compiled_insns.each do |idx, op, *arguments|
          next unless missed_insns.include?(op)
          next unless compiled_blocks.any? { |block| block === idx }

          # This instruction was compiled
          missed_insns.delete(op)
        end
      end

      unless missed_insns.empty?
        flunk "Expected to compile instructions #{missed_insns.join(", ")} but didn't.\nCompiled ranges: #{all_compiled_blocks.inspect}\niseq:\n#{disasm}"
      end
    end
  end

  def eval_with_jit(script, min_calls: 1, timeout: 1000)
    args = [
      "--disable-gems",
      "--yjit-call-threshold=#{min_calls}",
      "--yjit-stats"
    ]
    args << "-e" << script
    stats_r, stats_w = IO.pipe
    out, err, status = EnvUtil.invoke_ruby(args,
      '', true, true, timeout: timeout, ios: {3 => stats_w}
    )
    stats_w.close
    stats = stats_r.read
    stats = Marshal.load(stats) if !stats.empty?
    stats_r.close
    [status, out, err, stats]
  end
end
