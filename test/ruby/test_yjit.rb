# frozen_string_literal: true
require 'test/unit'
require 'envutil'
require 'tmpdir'

return unless YJIT.enabled?

# Tests for YJIT with assertions on compilation and side exits
# insipired by the MJIT tests in test/ruby/test_jit.rb
class TestYJIT < Test::Unit::TestCase
  def test_compile_putnil
    assert_compiles('nil', insns: %i[putnil], stdout: 'nil')
  end

  def test_compile_putobject
    assert_compiles('true', insns: %i[putobject], stdout: 'true')
    assert_compiles('123', insns: %i[putobject], stdout: '123')
    assert_compiles(':foo', insns: %i[putobject], stdout: ':foo')
  end

  def test_compile_opt_not
    assert_compiles('!false', insns: %i[opt_not], stdout: 'true')
    assert_compiles('!nil', insns: %i[opt_not], stdout: 'true')
    assert_compiles('!true', insns: %i[opt_not], stdout: 'false')
    assert_compiles('![]', insns: %i[opt_not], stdout: 'false')
  end

  def test_compile_opt_newarray
    assert_compiles('[]', insns: %i[newarray], stdout: '[]')
    assert_compiles('[1+1]', insns: %i[newarray opt_plus], stdout: '[2]')
    assert_compiles('[1,1+1,3,4,5,6]', insns: %i[newarray opt_plus], stdout: '[1, 2, 3, 4, 5, 6]')
  end

  def test_compile_opt_duparray
    assert_compiles('[1]', insns: %i[duparray], stdout: '[1]')
    assert_compiles('[1, 2, 3]', insns: %i[duparray], stdout: '[1, 2, 3]')
  end

  def test_compile_opt_nil_p
    assert_compiles('nil.nil?', insns: %i[opt_nil_p], stdout: 'true')
    assert_compiles('false.nil?', insns: %i[opt_nil_p], stdout: 'false')
    assert_compiles('true.nil?', insns: %i[opt_nil_p], stdout: 'false')
    assert_compiles('(-"").nil?', insns: %i[opt_nil_p], stdout: 'false')
    assert_compiles('123.nil?', insns: %i[opt_nil_p], stdout: 'false')
  end

  def test_compile_eq_fixnum
    assert_compiles('123 == 123', insns: %i[opt_eq], stdout: 'true')
    assert_compiles('123 == 456', insns: %i[opt_eq], stdout: 'false')
  end

  def test_compile_eq_string
    assert_compiles('-"" == -""', insns: %i[opt_eq], stdout: 'true')
    assert_compiles('-"foo" == -"foo"', insns: %i[opt_eq], stdout: 'true')
    assert_compiles('-"foo" == -"bar"', insns: %i[opt_eq], stdout: 'false')
  end

  def test_string_then_nil
    assert_compiles(<<~RUBY, insns: %i[opt_nil_p], stdout: 'true')
      def foo(val)
        val.nil?
      end

      foo("foo")
      foo(nil)
    RUBY
  end

  def test_nil_then_string
    assert_compiles(<<~RUBY, insns: %i[opt_nil_p], stdout: 'false')
      def foo(val)
        val.nil?
      end

      foo(nil)
      foo("foo")
    RUBY
  end

  def test_opt_length_in_method
    assert_compiles(<<~RUBY, insns: %i[opt_length], stdout: '5')
      def foo(str)
        str.length
      end

      foo("hello, ")
      foo("world")
    RUBY
  end

  def test_compile_opt_getinlinecache
    assert_compiles(<<~RUBY, insns: %i[opt_getinlinecache], stdout: '123', min_calls: 2)
      def get_foo
        FOO
      end

      FOO = 123

      get_foo # warm inline cache
      get_foo
    RUBY
  end

  def test_string_interpolation
    assert_compiles(<<~'RUBY', insns: %i[checktype concatstrings], stdout: '"foobar"', min_calls: 2)
      def make_str(foo, bar)
        "#{foo}#{bar}"
      end

      make_str("foo", "bar")
      make_str("foo", "bar")
    RUBY
  end

  def assert_compiles(test_script, insns: [], min_calls: 1, stdout: nil, exits: {})
    reset_stats = <<~RUBY
      YJIT.runtime_stats
      YJIT.reset_stats!
    RUBY

    print_stats = <<~RUBY
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
        stats: stats,
        iseqs: collect_iseqs(iseq),
        disasm: iseq.disasm
      })
    RUBY

    script = <<~RUBY
      _test_proc = proc {
        #{test_script}
      }
      #{reset_stats}
      p _test_proc.call
      #{print_stats}
    RUBY

    status, out, err, stats = eval_with_jit(script, min_calls: min_calls)

    assert status.success?, "exited with status #{status.to_i}, stderr:\n#{err}"

    assert_equal stdout.chomp, out.chomp if stdout

    runtime_stats = stats[:stats]
    iseqs = stats[:iseqs]
    disasm = stats[:disasm]

    if stats[:stats]
      # Only available when RUBY_DEBUG enabled
      recorded_exits = stats[:stats].select { |k, v| k.to_s.start_with?("exit_") }
      recorded_exits = recorded_exits.reject { |k, v| v == 0 }
      recorded_exits.transform_keys! { |k| k.to_s.gsub("exit_", "").to_sym }
      if exits != :any && exits != recorded_exits
        flunk "Expected #{exits.empty? ? "no" : exits.inspect} exits" \
          ", but got\n#{recorded_exits.inspect}"
      end
    end

    if stats[:stats]
      # Only available when RUBY_DEBUG enabled
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
