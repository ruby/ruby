# frozen_string_literal: true
require 'test/unit'
require 'envutil'
require 'tmpdir'

return unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

# Tests for YJIT with assertions on compilation and side exits
# insipired by the MJIT tests in test/ruby/test_jit.rb
class TestYJIT < Test::Unit::TestCase
  def test_yjit_in_ruby_description
    assert_includes(RUBY_DESCRIPTION, '+YJIT')
  end

  def test_yjit_in_version
    [
      %w(--version --yjit),
      %w(--version --disable-yjit --yjit),
      %w(--version --disable-yjit --enable-yjit),
      %w(--version --disable-yjit --enable=yjit),
      %w(--version --disable=yjit --yjit),
      %w(--version --disable=yjit --enable-yjit),
      %w(--version --disable=yjit --enable=yjit),
      *([
        %w(--version --jit),
        %w(--version --disable-jit --jit),
        %w(--version --disable-jit --enable-jit),
        %w(--version --disable-jit --enable=jit),
        %w(--version --disable=jit --yjit),
        %w(--version --disable=jit --enable-jit),
        %w(--version --disable=jit --enable=jit),
      ] if RUBY_PLATFORM.start_with?('x86_64-') && RUBY_PLATFORM !~ /mswin|mingw|msys/),
    ].each do |version_args|
      assert_in_out_err(version_args) do |stdout, stderr|
        assert_equal(RUBY_DESCRIPTION, stdout.first)
        assert_equal([], stderr)
      end
    end
  end

  def test_command_line_switches
    assert_in_out_err('--yjit-', '', [], /invalid option --yjit-/)
    assert_in_out_err('--yjithello', '', [], /invalid option --yjithello/)
    assert_in_out_err('--yjit-call-threshold', '', [], /--yjit-call-threshold needs an argument/)
    assert_in_out_err('--yjit-call-threshold=', '', [], /--yjit-call-threshold needs an argument/)
    assert_in_out_err('--yjit-greedy-versioning=1', '', [], /warning: argument to --yjit-greedy-versioning is ignored/)
  end

  def test_yjit_stats_and_v_no_error
    _stdout, stderr, _status = EnvUtil.invoke_ruby(%w(-v --yjit-stats), '', true, true)
    refute_includes(stderr, "NoMethodError")
  end

  def test_enable_from_env_var
    yjit_child_env = {'RUBY_YJIT_ENABLE' => '1'}
    assert_in_out_err([yjit_child_env, '--version'], '') do |stdout, stderr|
      assert_equal(RUBY_DESCRIPTION, stdout.first)
      assert_equal([], stderr)
    end
    assert_in_out_err([yjit_child_env, '-e puts RUBY_DESCRIPTION'], '', [RUBY_DESCRIPTION])
    assert_in_out_err([yjit_child_env, '-e p RubyVM::YJIT.enabled?'], '', ['true'])
  end

  def test_compile_setclassvariable
    script = 'class Foo; def self.foo; @@foo = 1; end; end; Foo.foo'
    assert_compiles(script, insns: %i[setclassvariable], result: 1)
  end

  def test_compile_getclassvariable
    script = 'class Foo; @@foo = 1; def self.foo; @@foo; end; end; Foo.foo'
    assert_compiles(script, insns: %i[getclassvariable], result: 1)
  end

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

  def test_compile_newrange
    assert_compiles('s = 1; (s..5)', insns: %i[newrange], result: 1..5)
    assert_compiles('s = 1; e = 5; (s..e)', insns: %i[newrange], result: 1..5)
    assert_compiles('s = 1; (s...5)', insns: %i[newrange], result: 1...5)
    assert_compiles('s = 1; (s..)', insns: %i[newrange], result: 1..)
    assert_compiles('e = 5; (..e)', insns: %i[newrange], result: ..5)
  end

  def test_compile_duphash
    assert_compiles('{ two: 2 }', insns: %i[duphash], result: { two: 2 })
  end

  def test_compile_newhash
    assert_compiles('{}', insns: %i[newhash], result: {})
    assert_compiles('{ two: 1 + 1 }', insns: %i[newhash], result: { two: 2 })
    assert_compiles('{ 1 + 1 => :two }', insns: %i[newhash], result: { 2 => :two })
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

  def test_compile_eq_symbol
    assert_compiles(':foo == :foo', insns: %i[opt_eq], result: true)
    assert_compiles(':foo == :bar', insns: %i[opt_eq], result: false)
    assert_compiles(':foo == "foo".to_sym', insns: %i[opt_eq], result: true)
  end

  def test_compile_eq_object
    assert_compiles(<<~RUBY, insns: %i[opt_eq], result: false)
      def eq(a, b)
        a == b
      end

      eq(Object.new, Object.new)
    RUBY

    assert_compiles(<<~RUBY, insns: %i[opt_eq], result: true)
      def eq(a, b)
        a == b
      end

      obj = Object.new
      eq(obj, obj)
    RUBY
  end

  def test_compile_eq_arbitrary_class
    assert_compiles(<<~RUBY, insns: %i[opt_eq], result: "yes")
      def eq(a, b)
        a == b
      end

      class Foo
        def ==(other)
          "yes"
        end
      end

      eq(Foo.new, Foo.new)
      eq(Foo.new, Foo.new)
    RUBY
  end

  def test_compile_opt_lt
    assert_compiles('1 < 2', insns: %i[opt_lt])
    assert_compiles('"a" < "b"', insns: %i[opt_lt])
  end

  def test_compile_opt_le
    assert_compiles('1 <= 2', insns: %i[opt_le])
    assert_compiles('"a" <= "b"', insns: %i[opt_le])
  end

  def test_compile_opt_gt
    assert_compiles('1 > 2', insns: %i[opt_gt])
    assert_compiles('"a" > "b"', insns: %i[opt_gt])
  end

  def test_compile_opt_ge
    assert_compiles('1 >= 2', insns: %i[opt_ge])
    assert_compiles('"a" >= "b"', insns: %i[opt_ge])
  end

  def test_compile_opt_plus
    assert_compiles('1 + 2', insns: %i[opt_plus])
    assert_compiles('"a" + "b"', insns: %i[opt_plus])
    assert_compiles('[:foo] + [:bar]', insns: %i[opt_plus])
  end

  def test_compile_opt_minus
    assert_compiles('1 - 2', insns: %i[opt_minus])
    assert_compiles('[:foo, :bar] - [:bar]', insns: %i[opt_minus])
  end

  def test_compile_opt_or
    assert_compiles('1 | 2', insns: %i[opt_or])
    assert_compiles('[:foo] | [:bar]', insns: %i[opt_or])
  end

  def test_compile_opt_and
    assert_compiles('1 & 2', insns: %i[opt_and])
    assert_compiles('[:foo, :bar] & [:bar]', insns: %i[opt_and])
  end

  def test_compile_set_and_get_global
    assert_compiles('$foo = 123; $foo', insns: %i[setglobal], result: 123)
  end

  def test_compile_putspecialobject
    assert_compiles('-> {}', insns: %i[putspecialobject])
  end

  def test_compile_tostring
    assert_no_exits('"i am a string #{true}"')
  end

  def test_compile_opt_aset
    assert_compiles('[1,2,3][2] = 4', insns: %i[opt_aset])
    assert_compiles('{}[:foo] = :bar', insns: %i[opt_aset])
    assert_compiles('[1,2,3][0..-1] = []', insns: %i[opt_aset])
    assert_compiles('"foo"[3] = "d"', insns: %i[opt_aset])
  end

  def test_compile_attr_set
    assert_no_exits(<<~EORB)
    class Foo
      attr_accessor :bar
    end

    foo = Foo.new
    foo.bar = 3
    foo.bar = 3
    foo.bar = 3
    foo.bar = 3
    EORB
  end

  def test_compile_regexp
    assert_no_exits('/#{true}/')
  end

  def test_compile_dynamic_symbol
    assert_compiles(':"#{"foo"}"', insns: %i[intern])
    assert_compiles('s = "bar"; :"foo#{s}"', insns: %i[intern])
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

  def test_setlocal_with_level
    assert_no_exits(<<~RUBY)
      def sum(arr)
        sum = 0
        arr.each do |x|
          sum += x
        end
        sum
      end

      sum([1,2,3])
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

  def test_opt_regexpmatch2
    assert_compiles(<<~RUBY, insns: %i[opt_regexpmatch2], result: 0)
      def foo(str)
        str =~ /foo/
      end

      foo("foobar")
    RUBY
  end

  def test_expandarray
    assert_compiles(<<~'RUBY', insns: %i[expandarray], result: [1, 2])
      a, b = [1, 2]
    RUBY
  end

  def test_expandarray_nil
    assert_compiles(<<~'RUBY', insns: %i[expandarray], result: [nil, nil])
      a, b = nil
      [a, b]
    RUBY
  end

  def test_getspecial_backref
    assert_compiles("'foo' =~ /(o)./; $&", insns: %i[getspecial], result: "oo")
    assert_compiles("'foo' =~ /(o)./; $`", insns: %i[getspecial], result: "f")
    assert_compiles("'foo' =~ /(o)./; $'", insns: %i[getspecial], result: "")
    assert_compiles("'foo' =~ /(o)./; $+", insns: %i[getspecial], result: "o")
    assert_compiles("'foo' =~ /(o)./; $1", insns: %i[getspecial], result: "o")
    assert_compiles("'foo' =~ /(o)./; $2", insns: %i[getspecial], result: nil)
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

  def test_opt_getinlinecache_slowpath
    assert_compiles(<<~RUBY, exits: { opt_getinlinecache: 1 }, result: [42, 42, 1, 1], min_calls: 2)
      class A
        FOO = 42
        class << self
          def foo
            _foo = nil
            FOO
          end
        end
      end

      result = []

      result << A.foo
      result << A.foo

      class << A
        FOO = 1
      end

      result << A.foo
      result << A.foo

      result
    RUBY
  end

  def test_string_interpolation
    assert_compiles(<<~'RUBY', insns: %i[objtostring anytostring concatstrings], result: "foobar", min_calls: 2)
      def make_str(foo, bar)
        "#{foo}#{bar}"
      end

      make_str("foo", "bar")
      make_str("foo", "bar")
    RUBY
  end

  def test_string_interpolation_cast
    assert_compiles(<<~'RUBY', insns: %i[objtostring anytostring concatstrings], result: "123")
      def make_str(foo, bar)
        "#{foo}#{bar}"
      end

      make_str(1, 23)
    RUBY
  end

  def test_checkkeyword
    assert_compiles(<<~'RUBY', insns: %i[checkkeyword], result: [2, 5])
      def foo(foo: 1+1)
        foo
      end

      [foo, foo(foo: 5)]
    RUBY
  end

  def test_struct_aref
    assert_compiles(<<~RUBY)
      def foo(obj)
        obj.foo
        obj.bar
      end

      Foo = Struct.new(:foo, :bar)
      foo(Foo.new(123))
      foo(Foo.new(123))
    RUBY
  end

  def test_struct_aset
    assert_compiles(<<~RUBY)
      def foo(obj)
        obj.foo = 123
        obj.bar = 123
      end

      Foo = Struct.new(:foo, :bar)
      foo(Foo.new(123))
      foo(Foo.new(123))
    RUBY
  end

  def test_super_iseq
    assert_compiles(<<~'RUBY', insns: %i[invokesuper opt_plus opt_mult], result: 15)
      class A
        def foo
          1 + 2
        end
      end

      class B < A
        def foo
          super * 5
        end
      end

      B.new.foo
    RUBY
  end

  def test_super_cfunc
    assert_compiles(<<~'RUBY', insns: %i[invokesuper], result: "Hello")
      class Gnirts < String
        def initialize
          super(-"olleH")
        end

        def to_s
          super().reverse
        end
      end

      Gnirts.new.to_s
    RUBY
  end

  # Tests calling a variadic cfunc with many args
  def test_build_large_struct
    assert_compiles(<<~RUBY, insns: %i[opt_send_without_block], min_calls: 2)
      ::Foo = Struct.new(:a, :b, :c, :d, :e, :f, :g, :h)

      def build_foo
        ::Foo.new(:a, :b, :c, :d, :e, :f, :g, :h)
      end

      build_foo
      build_foo
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

  def test_optarg_and_kwarg
    assert_no_exits(<<~'RUBY')
      def opt_and_kwarg(a, b=nil, c: nil)
      end

      2.times do
        opt_and_kwarg(1, 2, c: 3)
      end
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

  def test_no_excessive_opt_getinlinecache_invalidation
    assert_compiles(<<~'RUBY', exits: :any, result: :ok)
      objects = [Object.new, Object.new]

      objects.each do |o|
        class << o
          def foo
            Object
          end
        end
      end

      9000.times {
        objects[0].foo
        objects[1].foo
      }

      stats = RubyVM::YJIT.runtime_stats
      return :ok unless stats[:all_stats]
      return :ok if stats[:invalidation_count] < 10

      :fail
    RUBY
  end

  def assert_no_exits(script)
    assert_compiles(script)
  end

  ANY = Object.new
  def assert_compiles(test_script, insns: [], min_calls: 1, stdout: nil, exits: {}, result: ANY, frozen_string_literal: nil)
    reset_stats = <<~RUBY
      RubyVM::YJIT.runtime_stats
      RubyVM::YJIT.reset_stats!
    RUBY

    write_results = <<~RUBY
      stats = RubyVM::YJIT.runtime_stats

      def collect_blocks(blocks)
        blocks.sort_by(&:address).map { |b| [b.iseq_start_index, b.iseq_end_index] }
      end

      def collect_iseqs(iseq)
        iseq_array = iseq.to_a
        insns = iseq_array.last.grep(Array)
        blocks = RubyVM::YJIT.blocks_for(iseq)
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
        result: #{result == ANY ? "nil" : "result"},
        stats: stats,
        iseqs: collect_iseqs(iseq),
        disasm: iseq.disasm
      })
    RUBY

    script = <<~RUBY
      #{"# frozen_string_literal: true" if frozen_string_literal}
      _test_proc = -> {
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
