# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS='test/ruby/test_yjit.rb'

require 'test/unit'
require 'envutil'
require 'tmpdir'
require_relative '../lib/jit_support'

return unless JITSupport.yjit_supported?

require 'stringio'

# Tests for YJIT with assertions on compilation and side exits
# insipired by the RJIT tests in test/ruby/test_rjit.rb
class TestYJIT < Test::Unit::TestCase
  running_with_yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

  def test_yjit_in_ruby_description
    assert_includes(RUBY_DESCRIPTION, '+YJIT')
  end if running_with_yjit

  # Check that YJIT is in the version string
  def test_yjit_in_version
    [
      %w(--version --yjit),
      %w(--version --disable-yjit --yjit),
      %w(--version --disable-yjit --enable-yjit),
      %w(--version --disable-yjit --enable=yjit),
      %w(--version --disable=yjit --yjit),
      %w(--version --disable=yjit --enable-yjit),
      %w(--version --disable=yjit --enable=yjit),
      %w(--version --jit),
      %w(--version --disable-jit --jit),
      %w(--version --disable-jit --enable-jit),
      %w(--version --disable-jit --enable=jit),
      %w(--version --disable=jit --yjit),
      %w(--version --disable=jit --enable-jit),
      %w(--version --disable=jit --enable=jit),
    ].each do |version_args|
      assert_in_out_err(version_args) do |stdout, stderr|
        assert_equal(RUBY_DESCRIPTION, stdout.first)
        assert_equal([], stderr)
      end
    end
  end if running_with_yjit

  def test_command_line_switches
    assert_in_out_err('--yjit-', '', [], /invalid option --yjit-/)
    assert_in_out_err('--yjithello', '', [], /invalid option --yjithello/)
    #assert_in_out_err('--yjit-call-threshold', '', [], /--yjit-call-threshold needs an argument/)
    #assert_in_out_err('--yjit-call-threshold=', '', [], /--yjit-call-threshold needs an argument/)
  end

  def test_yjit_enable
    args = []
    args << "--disable=yjit" if RubyVM::YJIT.enabled?
    assert_separately(args, <<~'RUBY')
      refute_predicate RubyVM::YJIT, :enabled?
      refute_includes RUBY_DESCRIPTION, "+YJIT"

      RubyVM::YJIT.enable

      assert_predicate RubyVM::YJIT, :enabled?
      assert_includes RUBY_DESCRIPTION, "+YJIT"
    RUBY
  end

  def test_yjit_disable
    assert_separately(["--yjit", "--yjit-disable"], <<~'RUBY')
      refute_predicate RubyVM::YJIT, :enabled?
      refute_includes RUBY_DESCRIPTION, "+YJIT"

      RubyVM::YJIT.enable

      assert_predicate RubyVM::YJIT, :enabled?
      assert_includes RUBY_DESCRIPTION, "+YJIT"
    RUBY
  end

  def test_yjit_enable_stats_false
    assert_separately(["--yjit-disable", "--yjit-stats"], <<~RUBY, ignore_stderr: true)
      assert_false RubyVM::YJIT.enabled?
      assert_nil RubyVM::YJIT.runtime_stats

      RubyVM::YJIT.enable

      assert_true RubyVM::YJIT.enabled?
      assert_true RubyVM::YJIT.runtime_stats[:all_stats]
    RUBY
  end

  def test_yjit_enable_stats_true
    args = []
    args << "--disable=yjit" if RubyVM::YJIT.enabled?
    assert_separately(args, <<~RUBY, ignore_stderr: true)
      assert_false RubyVM::YJIT.enabled?
      assert_nil RubyVM::YJIT.runtime_stats

      RubyVM::YJIT.enable(stats: true)

      assert_true RubyVM::YJIT.enabled?
      assert_true RubyVM::YJIT.runtime_stats[:all_stats]
    RUBY
  end

  def test_yjit_enable_stats_quiet
    assert_in_out_err(['--yjit-disable', '-e', 'RubyVM::YJIT.enable(stats: true)']) do |_stdout, stderr, _status|
      assert_not_empty stderr
    end
    assert_in_out_err(['--yjit-disable', '-e', 'RubyVM::YJIT.enable(stats: :quiet)']) do |_stdout, stderr, _status|
      assert_empty stderr
    end
  end

  def test_yjit_enable_with_call_threshold
    assert_separately(%w[--yjit-disable --yjit-call-threshold=1], <<~RUBY)
      def not_compiled = nil
      def will_compile = nil
      def compiled_counts = RubyVM::YJIT.runtime_stats&.dig(:compiled_iseq_count)

      not_compiled
      assert_nil compiled_counts
      assert_false RubyVM::YJIT.enabled?

      RubyVM::YJIT.enable

      will_compile
      assert compiled_counts > 0
      assert_true RubyVM::YJIT.enabled?
    RUBY
  end

  def test_yjit_enable_with_monkey_patch
    assert_separately(%w[--yjit-disable], <<~RUBY)
      # This lets rb_method_entry_at(rb_mKernel, ...) return NULL
      Kernel.prepend(Module.new)

      # This must not crash with "undefined optimized method!"
      RubyVM::YJIT.enable
    RUBY
  end

  def test_yjit_stats_and_v_no_error
    _stdout, stderr, _status = invoke_ruby(%w(-v --yjit-stats), '', true, true)
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
  end if running_with_yjit

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

  def test_compile_opt_succ
    assert_compiles('1.succ', insns: %i[opt_succ], result: 2)
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
    assert_compiles('[1,2,3][2] = 4', insns: %i[opt_aset], frozen_string_literal: false)
    assert_compiles('{}[:foo] = :bar', insns: %i[opt_aset], frozen_string_literal: false)
    assert_compiles('[1,2,3][0..-1] = []', insns: %i[opt_aset], frozen_string_literal: false)
    assert_compiles('"foo"[3] = "d"', insns: %i[opt_aset], frozen_string_literal: false)
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

  def test_string_concat_utf8
    assert_compiles(<<~RUBY, frozen_string_literal: true, result: true)
      def str_cat_utf8
        s = String.new
        10.times { s << "✅" }
        s
      end

      str_cat_utf8 == "✅" * 10
    RUBY
  end

  def test_string_concat_ascii
    # Constant-get for classes (e.g. String, Encoding) can cause a side-exit in getinlinecache. For now, ignore exits.
    assert_compiles(<<~RUBY, exits: :any)
      str_arg = "b".encode(Encoding::ASCII)
      def str_cat_ascii(arg)
        s = String.new(encoding: Encoding::ASCII)
        10.times { s << arg }
        s
      end

      str_cat_ascii(str_arg) == str_arg * 10
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

  def test_compile_getconstant
    assert_compiles(<<~RUBY, insns: %i[getconstant], result: [], call_threshold: 1)
      def get_argv(klass)
        klass::ARGV
      end

      get_argv(Object)
    RUBY
  end

  def test_compile_getconstant_with_sp_offset
    assert_compiles(<<~RUBY, insns: %i[getconstant], result: 2, call_threshold: 1)
      class Foo
        Bar = 1
      end

      2.times do
        s = Foo # this opt_getconstant_path needs warmup, so 2.times is needed
        Class.new(Foo).const_set(:Bar, s::Bar)
      end
    RUBY
  end

  def test_compile_opt_getconstant_path
    assert_compiles(<<~RUBY, insns: %i[opt_getconstant_path], result: 123, call_threshold: 2)
      def get_foo
        FOO
      end

      FOO = 123

      get_foo # warm inline cache
      get_foo
    RUBY
  end

  def test_opt_getconstant_path_slowpath
    assert_compiles(<<~RUBY, exits: { opt_getconstant_path: 1 }, result: [42, 42, 1, 1], call_threshold: 2)
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

  def test_opt_getconstant_path_general
    assert_compiles(<<~RUBY, result: [1, 1])
      module Base
        Const = 1
      end

      class Sub
        def const
          _const = nil # make a non-entry block for opt_getconstant_path
          Const
        end

        def self.const_missing(n)
          Base.const_get(n)
        end
      end


      sub = Sub.new
      result = []
      result << sub.const # generate the general case
      result << sub.const # const_missing does not invalidate the block
      result
    RUBY
  end

  def test_string_interpolation
    assert_compiles(<<~'RUBY', insns: %i[objtostring anytostring concatstrings], result: "foobar", call_threshold: 2)
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

  def test_getblockparam
    assert_compiles(<<~'RUBY', insns: [:getblockparam])
      def foo &blk
        2.times do
          blk
        end
      end

      foo {}
      foo {}
    RUBY
  end

  def test_getblockparamproxy
    assert_compiles(<<~'RUBY', insns: [:getblockparamproxy], exits: {})
      def foo &blk
        p blk.call
        p blk.call
      end

      foo { 1 }
      foo { 2 }
    RUBY
  end

  def test_ifunc_getblockparamproxy
    assert_compiles(<<~'RUBY', insns: [:getblockparamproxy], exits: {})
      class Foo
        include Enumerable

        def each(&block)
          block.call 1
          block.call 2
          block.call 3
        end
      end

      foo = Foo.new
      foo.map { _1 * 2 }
      foo.map { _1 * 2 }
    RUBY
  end

  def test_send_blockarg
    assert_compiles(<<~'RUBY', insns: [:getblockparamproxy, :send], exits: {})
      def bar
      end

      def foo &blk
        bar(&blk)
        bar(&blk)
      end

      foo
      foo

      foo { }
      foo { }
    RUBY
  end

  def test_send_splat
    assert_compiles(<<~'RUBY', result: "3#1,2,3/P", exits: {})
      def internal_method(*args)
        "#{args.size}##{args.join(",")}"
      end

      def jit_method
        send(:internal_method, *[1, 2, 3]) + "/P"
      end

      jit_method
    RUBY
  end

  def test_send_multiarg
    assert_compiles(<<~'RUBY', result: "3#1,2,3/Q")
      def internal_method(*args)
        "#{args.size}##{args.join(",")}"
      end

      def jit_method
        send(:internal_method, 1, 2, 3) + "/Q"
      end

      jit_method
    RUBY
  end

  def test_send_kwargs
    # For now, this side-exits when calls include keyword args
    assert_compiles(<<~'RUBY', result: "2#a:1,b:2/A")
      def internal_method(**kw)
        "#{kw.size}##{kw.keys.map { |k| "#{k}:#{kw[k]}" }.join(",")}"
      end

      def jit_method
        send(:internal_method, a: 1, b: 2) + "/A"
      end
      jit_method
    RUBY
  end

  def test_send_kwargs_in_receiver_only
    assert_compiles(<<~'RUBY', result: "0/RK", exits: {})
      def internal_method(**kw)
        "#{kw.size}"
      end

      def jit_method
        send(:internal_method) + "/RK"
      end
      jit_method
    RUBY
  end

  def test_send_with_underscores
    assert_compiles(<<~'RUBY', result: "0/RK", exits: {})
      def internal_method(**kw)
        "#{kw.size}"
      end

      def jit_method
        __send__(:internal_method) + "/RK"
      end
      jit_method
    RUBY
  end

  def test_send_kwargs_splat
    # For now, this side-exits when calling with a splat
    assert_compiles(<<~'RUBY', result: "2#a:1,b:2/B")
      def internal_method(**kw)
        "#{kw.size}##{kw.keys.map { |k| "#{k}:#{kw[k]}" }.join(",")}"
      end

      def jit_method
        send(:internal_method, **{ a: 1, b: 2 }) + "/B"
      end
      jit_method
    RUBY
  end

  def test_send_block
    # Setlocal_wc_0 sometimes side-exits on write barrier
    assert_compiles(<<~'RUBY', result: "b:n/b:y/b:y/b:n")
      def internal_method(&b)
        "b:#{block_given? ? "y" : "n"}"
      end

      def jit_method
        b7 = proc { 7 }
        [
          send(:internal_method),
          send(:internal_method, &b7),
          send(:internal_method) { 7 },
          send(:internal_method, &nil),
        ].join("/")
      end
      jit_method
    RUBY
  end

  def test_send_block_calling
    assert_compiles(<<~'RUBY', result: "1a2", exits: {})
      def internal_method
        out = yield
        "1" + out + "2"
      end

      def jit_method
        __send__(:internal_method) { "a" }
      end
      jit_method
    RUBY
  end

  def test_send_block_only_receiver
    assert_compiles(<<~'RUBY', result: "b:n", exits: {})
      def internal_method(&b)
        "b:#{block_given? ? "y" : "n"}"
      end

      def jit_method
        send(:internal_method)
      end
      jit_method
    RUBY
  end

  def test_send_block_only_sender
    assert_compiles(<<~'RUBY', result: "Y/Y/Y/Y", exits: {})
      def internal_method
        "Y"
      end

      def jit_method
        b7 = proc { 7 }
        [
          send(:internal_method),
          send(:internal_method, &b7),
          send(:internal_method) { 7 },
          send(:internal_method, &nil),
        ].join("/")
      end
      jit_method
    RUBY
  end

  def test_multisend
    assert_compiles(<<~'RUBY', result: "77")
      def internal_method
        "7"
      end

      def jit_method
        send(:send, :internal_method) + send(:send, :send, :internal_method)
      end
      jit_method
    RUBY
  end

  def test_getivar_opt_plus
    assert_no_exits(<<~RUBY)
      class TheClass
        def initialize
            @levar = 1
        end

        def get_sum
            sum = 0
            # The type of levar is unknown,
            # but this still should not exit
            sum += @levar
            sum
        end
      end

      obj = TheClass.new
      obj.get_sum
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

  def test_super_with_alias
    assert_compiles(<<~'RUBY', insns: %i[invokesuper opt_plus opt_mult], result: 15)
      class A
        def foo = 1 + 2
      end

      module M
        def foo = super() * 5
        alias bar foo

        def foo = :bad
      end

      A.prepend M

      A.new.bar
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
    assert_compiles(<<~RUBY, insns: %i[opt_send_without_block], call_threshold: 2)
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

  def test_cfunc_kwarg
    assert_no_exits('{}.store(:value, foo: 123)')
    assert_no_exits('{}.store(:value, foo: 123, bar: 456, baz: 789)')
    assert_no_exits('{}.merge(foo: 123)')
    assert_no_exits('{}.merge(foo: 123, bar: 456, baz: 789)')
  end

  # regression test simplified from URI::Generic#hostname=
  def test_ctx_different_mappings
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

  def test_int_equal
    assert_compiles(<<~'RUBY', exits: :any, result: [true, false, true, false, true, false, true, false])
      def eq(a, b)
        a == b
      end

      def eqq(a, b)
        a === b
      end

      big1 = 2 ** 65
      big2 = big1 + 1
      [eq(1, 1), eq(1, 2), eq(big1, big1), eq(big1, big2), eqq(1, 1), eqq(1, 2), eqq(big1, big1), eqq(big1, big2)]
    RUBY
  end

  def test_opt_case_dispatch
    assert_compiles(<<~'RUBY', exits: :any, result: [:"1", "2", 3])
      def case_dispatch(val)
        case val
        when 1
          :"#{val}"
        when 2
          "#{val}"
        else
          val
        end
      end

      [case_dispatch(1), case_dispatch(2), case_dispatch(3)]
    RUBY
  end

  def test_code_gc
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: :ok)
      return :not_paged unless add_pages(100) # prepare freeable pages
      RubyVM::YJIT.code_gc # first code GC
      return :not_compiled1 unless compiles { nil } # should be JITable again

      RubyVM::YJIT.code_gc # second code GC
      return :not_compiled2 unless compiles { nil } # should be JITable again

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count != 2

      :ok
    RUBY
  end

  def test_on_stack_code_gc_call
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: :ok)
      fiber = Fiber.new {
        # Loop to call the same basic block again after Fiber.yield
        while true
          Fiber.yield(nil.to_i)
        end
      }

      return :not_paged1 unless add_pages(400) # go to a page without initial ocb code
      return :broken_resume1 if fiber.resume != 0 # JIT the fiber
      RubyVM::YJIT.code_gc # first code GC, which should not free the fiber page
      return :broken_resume2 if fiber.resume != 0 # The code should be still callable

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count != 1

      :ok
    RUBY
  end

  def test_on_stack_code_gc_twice
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: :ok)
      fiber = Fiber.new {
        # Loop to call the same basic block again after Fiber.yield
        while Fiber.yield(nil.to_i); end
      }

      return :not_paged1 unless add_pages(400) # go to a page without initial ocb code
      return :broken_resume1 if fiber.resume(true) != 0 # JIT the fiber
      RubyVM::YJIT.code_gc # first code GC, which should not free the fiber page

      return :not_paged2 unless add_pages(300) # add some stuff to be freed
      # Not calling fiber.resume here to test the case that the YJIT payload loses some
      # information at the previous code GC. The payload should still be there, and
      # thus we could know the fiber ISEQ is still on stack on this second code GC.
      RubyVM::YJIT.code_gc # second code GC, which should still not free the fiber page

      return :not_paged3 unless add_pages(200) # attempt to overwrite the fiber page (it shouldn't)
      return :broken_resume2 if fiber.resume(true) != 0 # The fiber code should be still fine

      return :broken_resume3 if fiber.resume(false) != nil # terminate the fiber
      RubyVM::YJIT.code_gc # third code GC, freeing a page that used to be on stack

      return :not_paged4 unless add_pages(100) # check everything still works

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count != 3

      :ok
    RUBY
  end

  def test_disable_code_gc_with_many_iseqs
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: :ok, mem_size: 1, code_gc: false)
      fiber = Fiber.new {
        # Loop to call the same basic block again after Fiber.yield
        while true
          Fiber.yield(nil.to_i)
        end
      }

      return :not_paged1 unless add_pages(250) # use some pages
      return :broken_resume1 if fiber.resume != 0 # leave an on-stack code as well

      add_pages(2000) # use a whole lot of pages to run out of 1MiB
      return :broken_resume2 if fiber.resume != 0 # on-stack code should be callable

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count != 0

      :ok
    RUBY
  end

  def test_code_gc_with_many_iseqs
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: :ok, mem_size: 1, code_gc: true)
      fiber = Fiber.new {
        # Loop to call the same basic block again after Fiber.yield
        while true
          Fiber.yield(nil.to_i)
        end
      }

      return :not_paged1 unless add_pages(250) # use some pages
      return :broken_resume1 if fiber.resume != 0 # leave an on-stack code as well

      add_pages(2000) # use a whole lot of pages to run out of 1MiB
      return :broken_resume2 if fiber.resume != 0 # on-stack code should be callable

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count == 0

      :ok
    RUBY
  end

  def test_code_gc_with_auto_compact
    assert_compiles((code_gc_helpers + <<~'RUBY'), exits: :any, result: :ok, mem_size: 1, code_gc: true)
      # Test ISEQ moves in the middle of code GC
      GC.auto_compact = true

      fiber = Fiber.new {
        # Loop to call the same basic block again after Fiber.yield
        while true
          Fiber.yield(nil.to_i)
        end
      }

      return :not_paged1 unless add_pages(250) # use some pages
      return :broken_resume1 if fiber.resume != 0 # leave an on-stack code as well

      add_pages(2000) # use a whole lot of pages to run out of 1MiB
      return :broken_resume2 if fiber.resume != 0 # on-stack code should be callable

      code_gc_count = RubyVM::YJIT.runtime_stats[:code_gc_count]
      return :"code_gc_#{code_gc_count}" if code_gc_count == 0

      :ok
    RUBY
  end

  def test_code_gc_partial_last_page
    # call_threshold: 2 to avoid JIT-ing code_gc itself. If code_gc were JITed right before
    # code_gc is called, the last page would be on stack.
    assert_compiles(<<~'RUBY', exits: :any, result: :ok, call_threshold: 2)
      # Leave a bunch of off-stack pages
      i = 0
      while i < 1000
        eval("x = proc { 1.to_s }; x.call; x.call")
        i += 1
      end

      # On Linux, memory page size != code page size. So the last code page could be partially
      # mapped. This call tests that assertions and other things work fine under the situation.
      RubyVM::YJIT.code_gc

      :ok
    RUBY
  end

  def test_trace_script_compiled # not ISEQ_TRACE_EVENTS
    assert_compiles(<<~'RUBY', exits: :any, result: :ok)
      @eval_counter = 0
      def eval_script
        eval('@eval_counter += 1')
      end

      @trace_counter = 0
      trace = TracePoint.new(:script_compiled) do |t|
        @trace_counter += 1
      end

      eval_script # JIT without TracePoint
      trace.enable
      eval_script # call with TracePoint
      trace.disable

      return :"eval_#{@eval_counter}" if @eval_counter != 2
      return :"trace_#{@trace_counter}" if @trace_counter != 1

      :ok
    RUBY
  end

  def test_trace_b_call # ISEQ_TRACE_EVENTS
    assert_compiles(<<~'RUBY', exits: :any, result: :ok)
      @call_counter = 0
      def block_call
        1.times { @call_counter += 1 }
      end

      @trace_counter = 0
      trace = TracePoint.new(:b_call) do |t|
        @trace_counter += 1
      end

      block_call # JIT without TracePoint
      trace.enable
      block_call # call with TracePoint
      trace.disable

      return :"call_#{@call_counter}" if @call_counter != 2
      return :"trace_#{@trace_counter}" if @trace_counter != 1

      :ok
    RUBY
  end

  def test_send_to_call
    assert_compiles(<<~'RUBY', result: :ok)
      ->{ :ok }.send(:call)
    RUBY
  end

  def test_invokeblock_many_locals
    # [Bug #19299]
    assert_compiles(<<~'RUBY', result: :ok)
      def foo
        yield
      end

      foo do
        a1=a2=a3=a4=a5=a6=a7=a8=a9=a10=a11=a12=a13=a14=a15=a16=a17=a18=a19=a20=a21=a22=a23=a24=a25=a26=a27=a28=a29=a30 = :ok
        a30
      end
    RUBY
  end

  def test_bug_19316
    n = 2 ** 64
    # foo's extra param and the splats are relevant
    assert_compiles(<<~'RUBY', result: [[n, -n], [n, -n]], exits: :any)
      def foo(_, a, b, c)
        [a & b, ~c]
      end

      n = 2 ** 64
      args = [0, -n, n, n-1]

      GC.stress = true
      [foo(*args), foo(*args)]
    RUBY
  end

  def test_gc_compact_cyclic_branch
    assert_compiles(<<~'RUBY', result: 2)
      def foo
        i = 0
        while i < 2
          i += 1
        end
        i
      end

      foo
      GC.compact
      foo
    RUBY
  end

  def test_invalidate_cyclic_branch
    assert_compiles(<<~'RUBY', result: 2, exits: { opt_plus: 1 })
      def foo
        i = 0
        while i < 2
          i += 1
        end
        i
      end

      foo
      class Integer
        def +(x) = self - -x
      end
      foo
    RUBY
  end

  def test_tracing_str_uplus
    assert_compiles(<<~RUBY, frozen_string_literal: true, result: :ok, exits: { putspecialobject: 1, definemethod: 1 })
      def str_uplus
        _ = 1
        _ = 2
        ret = [+"frfr", __LINE__]
        _ = 3
        _ = 4

        ret
      end

      str_uplus
      require 'objspace'
      ObjectSpace.trace_object_allocations_start

      str, expected_line = str_uplus
      alloc_line = ObjectSpace.allocation_sourceline(str)

      if expected_line == alloc_line
        :ok
      else
        [expected_line, alloc_line]
      end
    RUBY
  end

  def test_str_uplus_subclass
    assert_compiles(<<~RUBY, frozen_string_literal: true, result: :subclass)
      class S < String
        def encoding
          :subclass
        end
      end

      def test(str)
        (+str).encoding
      end

      test ""
      test S.new
    RUBY
  end

  def test_return_to_invalidated_block
    # [Bug #19463]
    assert_compiles(<<~RUBY, result: [1, 1, :ugokanai], exits: { definesmethod: 1, getlocal_WC_0: 1 })
      klass = Class.new do
        def self.lookup(hash, key) = hash[key]

        def self.foo(a, b) = []

        def self.test(hash, key)
          [lookup(hash, key), key, "".freeze]
          # 05 opt_send_without_block :lookup
          # 07 getlocal_WC_0          :hash
          # 09 opt_str_freeze         ""
          # 12 newarray               3
          # 14 leave
          #
          # YJIT will put instructions (07..14) into a block.
          # When String#freeze is redefined from within lookup(),
          # the return address to the block is still on-stack. We rely
          # on invalidation patching the code at the return address
          # to service this situation correctly.
        end
      end

      # get YJIT to compile test()
      hash = { 1 => [] }
      31.times { klass.test(hash, 1) }

      # inject invalidation into lookup()
      evil_hash = Hash.new do |_, key|
        class String
          undef :freeze
          def freeze = :ugokanai
        end

        key
      end
      klass.test(evil_hash, 1)
    RUBY
  end

  def test_return_to_invalidated_frame
    assert_compiles(code_gc_helpers + <<~RUBY, exits: :any, result: :ok)
      def jump
        [] # something not inlined
      end

      def entry(code_gc)
        jit_exception(code_gc)
        jump # faulty jump after code GC. #jit_exception should not come back.
      end

      def jit_exception(code_gc)
        if code_gc
          tap do
            RubyVM::YJIT.code_gc
            break # jit_exec_exception catches TAG_BREAK and re-enters JIT code
          end
        end
      end

      add_pages(100)
      jump           # Compile #jump in a non-first page
      add_pages(100)
      entry(false)   # Compile #entry and its call to #jump in another page
      entry(true)    # Free #jump but not #entry

      :ok
    RUBY
  end

  def test_setivar_on_class
    # Bug in https://github.com/ruby/ruby/pull/8152
    assert_compiles(<<~RUBY, result: :ok)
      class Base
        def self.or_equal
          @or_equal ||= Object.new
        end
      end

      Base.or_equal # ensure compiled

      class Child < Base
      end

      200.times do |iv| # Need to be more than MAX_IVAR
        Child.instance_variable_set("@_iv_\#{iv}", Object.new)
      end

      Child.or_equal
      :ok
    RUBY
  end

  def test_nested_send
    #[Bug #19464]
    assert_compiles(<<~RUBY, result: [:ok, :ok], exits: { defineclass: 1 })
      klass = Class.new do
        class << self
          alias_method :my_send, :send

          def bar = :ok

          def foo = bar
        end
      end

      with_break = -> { break klass.send(:my_send, :foo) }
      wo_break = -> { klass.send(:my_send, :foo) }

      [with_break[], wo_break[]]
    RUBY
  end

  def test_str_concat_encoding_mismatch
    assert_compiles(<<~'RUBY', result: "incompatible character encodings: BINARY (ASCII-8BIT) and EUC-JP")
      def bar(a, b)
        a << b
      rescue => e
        e.message
      end

      def foo(a, b, h)
        h[nil]
        bar(a, b) # Ruby call, not set cfp->pc
      end

      h = Hash.new { nil }
      foo("\x80".b, "\xA1A1".dup.force_encoding("EUC-JP"), h)
      foo("\x80".b, "\xA1A1".dup.force_encoding("EUC-JP"), h)
    RUBY
  end

  def test_io_reopen_clobbering_singleton_class
    assert_compiles(<<~RUBY, result: [:ok, :ok], exits: { definesmethod: 1, opt_eq: 2 })
      def $stderr.to_i = :i

      def test = $stderr.to_i

      [test, test]
      $stderr.reopen($stderr.dup)
      [test, test].map { :ok unless _1 == :i }
    RUBY
  end

  def test_opt_aref_with
    assert_compiles(<<~RUBY, insns: %i[opt_aref_with], result: "bar", frozen_string_literal: false)
      h = {"foo" => "bar"}

      h["foo"]
    RUBY
  end

  def test_proc_block_arg
    assert_compiles(<<~RUBY, result: [:proc, :no_block])
      def yield_if_given = block_given? ? yield : :no_block

      def call(block_arg = nil) = yield_if_given(&block_arg)

      [call(-> { :proc }), call]
    RUBY
  end

  def test_opt_mult_overflow
    assert_no_exits('0xfff_ffff_ffff_ffff * 0x10')
  end

  def test_disable_stats
    assert_in_out_err(%w[--yjit-stats --yjit-disable])
  end

  def test_odd_calls_to_attr_reader
    # Use of delegate from ActiveSupport use these kind of calls to getter methods.
    assert_compiles(<<~RUBY, result: [1, 1, 1], no_send_fallbacks: true)
      class One
        attr_reader :one
        def initialize
          @one = 1
        end
      end

      def calls(obj, empty, &)
        [obj.one(*empty), obj.one(&), obj.one(*empty, &)]
      end

      calls(One.new, [])
    RUBY
  end

  def test_kwrest
    assert_compiles(<<~RUBY, result: true, no_send_fallbacks: true)
      def req_rest(r1:, **kwrest) = [r1, kwrest]
      def opt_rest(r1: 1.succ, **kwrest) = [r1, kwrest]
      def kwrest(**kwrest) = kwrest

      def calls
        [
          [1, {}] == req_rest(r1: 1),
          [1, {:r2=>2, :r3=>3}] == req_rest(r1: 1, r2: 2, r3: 3),
          [1, {:r2=>2, :r3=>3}] == req_rest(r2: 2, r1:1, r3: 3),
          [1, {:r2=>2, :r3=>3}] == req_rest(r2: 2, r3: 3, r1: 1),

          [2, {}] == opt_rest,
          [2, { r2: 2, r3: 3 }] == opt_rest(r2: 2, r3: 3),
          [0, { r2: 2, r3: 3 }] == opt_rest(r1: 0, r3: 3, r2: 2),
          [0, { r2: 2, r3: 3 }] == opt_rest(r2: 2, r1: 0, r3: 3),
          [1, { r2: 2, r3: 3 }] == opt_rest(r2: 2, r3: 3, r1: 1),

          {} == kwrest,
          { r0: 88, r1: 99 } == kwrest(r0: 88, r1: 99),
        ]
      end

      calls.all?
    RUBY
  end

  def test_send_polymorphic_method_name
    assert_compiles(<<~'RUBY', result: %i[ok ok], no_send_fallbacks: true)
      mid = "dynamic_mid_#{rand(100..200)}"
      mid_dsym = mid.to_sym

      define_method(mid) { :ok }

      define_method(:send_site) { send(_1) }

      [send_site(mid), send_site(mid_dsym)]
    RUBY
  end

  def test_kw_splat_nil
    assert_compiles(<<~'RUBY', result: %i[ok ok ok], no_send_fallbacks: true)
      def id(x) = x
      def kw_fw(arg, **) = id(arg, **)
      def fw(...) = id(...)
      def use = [fw(:ok), kw_fw(:ok), :ok.itself(**nil)]

      use
    RUBY
  end

  def test_empty_splat
    assert_compiles(<<~'RUBY', result: %i[ok ok], no_send_fallbacks: true)
      def foo = :ok
      def fw(...) = foo(...)
      def use(empty) = [foo(*empty), fw]

      use([])
    RUBY
  end

  def test_byteslice_sp_invalidation
    assert_compiles(<<~'RUBY', result: 'ok', no_send_fallbacks: true)
      "okng".itself.byteslice(0, 2)
    RUBY
  end

  def test_leaf_builtin
    assert_compiles(code_gc_helpers + <<~'RUBY', exits: :any, result: 1)
      before = RubyVM::YJIT.runtime_stats[:num_send_iseq_leaf]
      return 1 if before.nil?

      def entry = self.class
      entry

      after = RubyVM::YJIT.runtime_stats[:num_send_iseq_leaf]
      after - before
    RUBY
  end

  private

  def code_gc_helpers
    <<~'RUBY'
      def compiles(&block)
        failures = RubyVM::YJIT.runtime_stats[:compilation_failure]
        block.call
        failures == RubyVM::YJIT.runtime_stats[:compilation_failure]
      end

      def add_pages(num_jits)
        pages = RubyVM::YJIT.runtime_stats[:live_page_count]
        num_jits.times { return false unless eval('compiles { nil.to_i }') }
        pages.nil? || pages < RubyVM::YJIT.runtime_stats[:live_page_count]
      end
    RUBY
  end

  def assert_no_exits(script)
    assert_compiles(script)
  end

  ANY = Object.new
  def assert_compiles(
    test_script, insns: [],
    call_threshold: 1,
    stdout: nil,
    exits: {},
    result: ANY,
    frozen_string_literal: nil,
    mem_size: nil,
    code_gc: false,
    no_send_fallbacks: false
  )
    reset_stats = <<~RUBY
      RubyVM::YJIT.runtime_stats
      RubyVM::YJIT.reset_stats!
    RUBY

    write_results = <<~RUBY
      stats = RubyVM::YJIT.runtime_stats

      def collect_insns(iseq)
        insns = RubyVM::YJIT.insns_compiled(iseq)
        iseq.each_child { |c| insns.concat collect_insns(c) }
        insns
      end

      iseq = RubyVM::InstructionSequence.of(_test_proc)
      IO.open(3).write Marshal.dump({
        result: #{result == ANY ? "nil" : "result"},
        stats: stats,
        insns: collect_insns(iseq),
        disasm: iseq.disasm
      })
    RUBY

    script = <<~RUBY
      #{"# frozen_string_literal: " + frozen_string_literal.to_s unless frozen_string_literal.nil?}
      _test_proc = -> {
        #{test_script}
      }
      #{reset_stats}
      result = _test_proc.call
      #{write_results}
    RUBY

    status, out, err, stats = eval_with_jit(script, call_threshold:, mem_size:, code_gc:)

    assert status.success?, "exited with status #{status.to_i}, stderr:\n#{err}"

    assert_equal stdout.chomp, out.chomp if stdout

    unless ANY.equal?(result)
      assert_equal result, stats[:result]
    end

    runtime_stats = stats[:stats]
    insns_compiled = stats[:insns]
    disasm = stats[:disasm]

    # Check that exit counts are as expected
    # Full stats are only available when --enable-yjit=dev
    if runtime_stats[:all_stats]
      recorded_exits = runtime_stats.select { |k, v| k.to_s.start_with?("exit_") }
      recorded_exits = recorded_exits.reject { |k, v| v == 0 }

      recorded_exits.transform_keys! { |k| k.to_s.gsub("exit_", "").to_sym }
      # Exits can be specified as a hash of stat-name symbol to integer for exact exits.
      # or stat-name symbol to range if the number of side exits might vary (e.g. write
      # barriers, cache misses.)
      if exits != :any &&
        exits != recorded_exits &&
        (exits.keys != recorded_exits.keys || !exits.all? { |k, v| v === recorded_exits[k] }) # triple-equal checks range membership or integer equality
        stats_reasons = StringIO.new
        ::RubyVM::YJIT.send(:_print_stats_reasons, runtime_stats, stats_reasons)
        stats_reasons = stats_reasons.string
        flunk <<~EOM
          Expected #{exits.empty? ? "no" : exits.inspect} exits, but got:
          #{recorded_exits.inspect}
          Reasons:
          #{stats_reasons}
        EOM
      end
    end

    if no_send_fallbacks
      assert_equal(0, runtime_stats[:num_send_dynamic], "Expected no use of fallback implementation")
    end

    # Only available when --enable-yjit=dev
    if runtime_stats[:all_stats]
      missed_insns = insns.dup

      insns_compiled.each do |op|
        if missed_insns.include?(op)
          # This instruction was compiled
          missed_insns.delete(op)
        end
      end

      unless missed_insns.empty?
        flunk "Expected to compile instructions #{missed_insns.join(", ")} but didn't.\niseq:\n#{disasm}"
      end
    end
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end

  def eval_with_jit(script, call_threshold: 1, timeout: 1000, mem_size: nil, code_gc: false)
    args = [
      "--disable-gems",
      "--yjit-call-threshold=#{call_threshold}",
      "--yjit-stats=quiet"
    ]
    args << "--yjit-exec-mem-size=#{mem_size}" if mem_size
    args << "--yjit-code-gc" if code_gc
    args << "-e" << script_shell_encode(script)
    stats_r, stats_w = IO.pipe
    # Separate thread so we don't deadlock when
    # the child ruby blocks writing the stats to fd 3
    stats = ''
    stats_reader = Thread.new do
      stats = stats_r.read
      stats_r.close
    end
    out, err, status = invoke_ruby(args, '', true, true, timeout: timeout, ios: { 3 => stats_w })
    stats_w.close
    stats_reader.join(timeout)
    stats = Marshal.load(stats) if !stats.empty?
    [status, out, err, stats]
  ensure
    stats_reader&.kill
    stats_reader&.join(timeout)
    stats_r&.close
    stats_w&.close
  end

  # A wrapper of EnvUtil.invoke_ruby that uses RbConfig.ruby instead of EnvUtil.ruby
  # that might use a wrong Ruby depending on your environment.
  def invoke_ruby(*args, **kwargs)
    EnvUtil.invoke_ruby(*args, rubybin: RbConfig.ruby, **kwargs)
  end
end
