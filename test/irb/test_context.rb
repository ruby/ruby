# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require 'irb'
require 'rubygems' if defined?(Gem)

module TestIRB
  class TestContext < Test::Unit::TestCase
    class TestInputMethod < ::IRB::InputMethod
      attr_reader :list, :line_no

      def initialize(list = [])
        super("test")
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end

      def winsize
        [10, 20]
      end
    end

    def setup
      IRB.init_config(nil)
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(Object.new)
      @context = IRB::Context.new(nil, workspace, TestInputMethod.new)

      @get_screen_size = Reline.method(:get_screen_size)
      Reline.instance_eval { undef :get_screen_size }
      def Reline.get_screen_size
        [36, 80]
      end
    end

    def teardown
      Reline.instance_eval { undef :get_screen_size }
      Reline.define_singleton_method(:get_screen_size, @get_screen_size)
    end

    def test_last_value
      assert_nil(@context.last_value)
      assert_nil(@context.evaluate('_', 1))
      obj = Object.new
      @context.set_last_value(obj)
      assert_same(obj, @context.last_value)
      assert_same(obj, @context.evaluate('_', 1))
    end

    def test_evaluate_with_exception
      assert_nil(@context.evaluate("$!", 1))
      e = assert_raise_with_message(RuntimeError, 'foo') {
        @context.evaluate("raise 'foo'", 1)
      }
      assert_equal('foo', e.message)
      assert_same(e, @context.evaluate('$!', 1, exception: e))
      e = assert_raise(SyntaxError) {
        @context.evaluate("1,2,3", 1, exception: e)
      }
      assert_match(/\A\(irb\):1:/, e.message)
      assert_not_match(/rescue _\.class/, e.message)
    end

    def test_evaluate_with_encoding_error_without_lineno
      skip if RUBY_ENGINE == 'truffleruby'
      assert_raise_with_message(EncodingError, /invalid symbol/) {
        @context.evaluate(%q[{"\xAE": 1}], 1)
        # The backtrace of this invalid encoding hash doesn't contain lineno.
      }
    end

    def test_evaluate_with_onigmo_warning
      skip if RUBY_ENGINE == 'truffleruby'
      assert_warning("(irb):1: warning: character class has duplicated range: /[aa]/\n") do
        @context.evaluate('/[aa]/', 1)
      end
    end

    def test_eval_input
      skip if RUBY_ENGINE == 'truffleruby'
      verbose, $VERBOSE = $VERBOSE, nil
      input = TestInputMethod.new([
        "raise 'Foo'\n",
        "_\n",
        "0\n",
        "_\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_pattern_list([:*, /\(irb\):1:in `<main>': Foo \(RuntimeError\)\n/,
                           :*, /#<RuntimeError: Foo>\n/,
                           :*, /0$/,
                           :*, /0$/,
                           /\s*/], out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_raise2x
      skip if RUBY_ENGINE == 'truffleruby'
      input = TestInputMethod.new([
        "raise 'Foo'\n",
        "raise 'Bar'\n",
        "_\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_pattern_list([
          :*, /\(irb\):1:in `<main>': Foo \(RuntimeError\)\n/,
          :*, /\(irb\):2:in `<main>': Bar \(RuntimeError\)\n/,
          :*, /#<RuntimeError: Bar>\n/,
        ], out)
    end

    def test_eval_object_without_inspect_method
      verbose, $VERBOSE = $VERBOSE, nil
      all_assertions do |all|
        IRB::Inspector::INSPECTORS.invert.each_value do |mode|
          all.for(mode) do
            input = TestInputMethod.new([
                "[BasicObject.new, Class.new]\n",
              ])
            irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
            irb.context.inspect_mode = mode
            out, err = capture_output do
              irb.eval_input
            end
            assert_empty err
            assert_match(/\(Object doesn't support #inspect\)\n(=> )?\n/, out)
          end
        end
      end
    ensure
      $VERBOSE = verbose
    end

    def test_default_config
      assert_equal(true, @context.use_colorize?)
    end

    def test_assignment_expression
      input = TestInputMethod.new
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      [
        "foo = bar",
        "@foo = bar",
        "$foo = bar",
        "@@foo = bar",
        "::Foo = bar",
        "a::Foo = bar",
        "Foo = bar",
        "foo.bar = 1",
        "foo[1] = bar",
        "foo += bar",
        "foo -= bar",
        "foo ||= bar",
        "foo &&= bar",
        "foo, bar = 1, 2",
        "foo.bar=(1)",
        "foo; foo = bar",
        "foo; foo = bar; ;\n ;",
        "foo\nfoo = bar",
      ].each do |exp|
        assert(
          irb.assignment_expression?(exp),
          "#{exp.inspect}: should be an assignment expression"
        )
      end

      [
        "foo",
        "foo.bar",
        "foo[0]",
        "foo = bar; foo",
        "foo = bar\nfoo",
      ].each do |exp|
        refute(
          irb.assignment_expression?(exp),
          "#{exp.inspect}: should not be an assignment expression"
        )
      end
    end

    def test_echo_on_assignment
      input = TestInputMethod.new([
        "a = 1\n",
        "a\n",
        "a, b = 2, 3\n",
        "a\n",
        "b\n",
        "b = 4\n",
        "_\n"
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"

      # The default
      irb.context.echo = true
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> 1\n=> 2\n=> 3\n=> 4\n", out)

      # Everything is output, like before echo_on_assignment was introduced
      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> 1\n=> 1\n=> [2, 3]\n=> 2\n=> 3\n=> 4\n=> 4\n", out)

      # Nothing is output when echo is false
      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      # Nothing is output when echo is false even if echo_on_assignment is true
      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
    end

    def test_omit_on_assignment
      input = TestInputMethod.new([
        "a = [1] * 100\n",
        "a\n",
      ])
      value = [1] * 100
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"

      irb.context.echo = true
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = :truncate
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect[0..3]}...\n=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect}=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = :truncate
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
    end

    def test_omit_multiline_on_assignment
      input = TestInputMethod.new([
        "class A; def inspect; ([?* * 1000] * 3).join(%{\\n}); end; end; a = A.new\n",
        "a\n"
      ])
      value = ([?* * 1000] * 3).join(%{\n})
      value_first_line = (?* * 1000).to_s
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"

      irb.context.echo = true
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value}\n", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = :truncate
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> #{value_first_line[0..(input.winsize.last - 9)]}...\e[0m\n=> \n#{value}\n", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value}\n=> \n#{value}\n", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = :truncate
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
      irb.context.evaluate('A.remove_method(:inspect)', 0)
    end

    def test_echo_on_assignment_conf
      # Default
      IRB.conf[:ECHO] = nil
      IRB.conf[:ECHO_ON_ASSIGNMENT] = nil
      input = TestInputMethod.new()
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)

      assert(irb.context.echo?, "echo? should be true by default")
      assert_equal(:truncate, irb.context.echo_on_assignment?, "echo_on_assignment? should be :truncate by default")

      # Explicitly set :ECHO to false
      IRB.conf[:ECHO] = false
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)

      refute(irb.context.echo?, "echo? should be false when IRB.conf[:ECHO] is set to false")
      assert_equal(:truncate, irb.context.echo_on_assignment?, "echo_on_assignment? should be :truncate by default")

      # Explicitly set :ECHO_ON_ASSIGNMENT to true
      IRB.conf[:ECHO] = nil
      IRB.conf[:ECHO_ON_ASSIGNMENT] = false
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)

      assert(irb.context.echo?, "echo? should be true by default")
      refute(irb.context.echo_on_assignment?, "echo_on_assignment? should be false when IRB.conf[:ECHO_ON_ASSIGNMENT] is set to false")
    end

    def test_multiline_output_on_default_inspector
      main = Object.new
      def main.inspect
        "abc\ndef"
      end
      input = TestInputMethod.new([
        "self"
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
      irb.context.return_format = "=> %s\n"

      # The default
      irb.context.newline_before_multiline_output = true
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \nabc\ndef\n",
                   out)

      # No newline before multiline output
      input.reset
      irb.context.newline_before_multiline_output = false
      out, err = capture_io do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> abc\ndef\n",
                   out)
    end

    def test_eval_input_with_exception
      skip if RUBY_ENGINE == 'truffleruby'
      verbose, $VERBOSE = $VERBOSE, nil
      input = TestInputMethod.new([
        "def hoge() fuga; end; def fuga() raise; end; hoge\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      if '2.5.0' <= RUBY_VERSION && RUBY_VERSION < '3.0.0' && STDOUT.tty?
        expected = [
          :*, /Traceback \(most recent call last\):\n/,
          :*, /\t 2: from \(irb\):1:in `<main>'\n/,
          :*, /\t 1: from \(irb\):1:in `hoge'\n/,
          :*, /\(irb\):1:in `fuga': unhandled exception\n/,
        ]
      else
        expected = [
          :*, /\(irb\):1:in `fuga': unhandled exception\n/,
          :*, /\tfrom \(irb\):1:in `hoge'\n/,
          :*, /\tfrom \(irb\):1:in `<main>'\n/,
        ]
      end
      assert_pattern_list(expected, out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_with_invalid_byte_sequence_exception
      skip if RUBY_ENGINE == 'truffleruby'
      verbose, $VERBOSE = $VERBOSE, nil
      input = TestInputMethod.new([
        %Q{def hoge() fuga; end; def fuga() raise "A\\xF3B"; end; hoge\n},
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      if '2.5.0' <= RUBY_VERSION && RUBY_VERSION < '3.0.0' && STDOUT.tty?
        expected = [
          :*, /Traceback \(most recent call last\):\n/,
          :*, /\t 2: from \(irb\):1:in `<main>'\n/,
          :*, /\t 1: from \(irb\):1:in `hoge'\n/,
          :*, /\(irb\):1:in `fuga': A\\xF3B \(RuntimeError\)\n/,
        ]
      else
        expected = [
          :*, /\(irb\):1:in `fuga': A\\xF3B \(RuntimeError\)\n/,
          :*, /\tfrom \(irb\):1:in `hoge'\n/,
          :*, /\tfrom \(irb\):1:in `<main>'\n/,
        ]
      end
      assert_pattern_list(expected, out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_with_long_exception
      skip if RUBY_ENGINE == 'truffleruby'
      verbose, $VERBOSE = $VERBOSE, nil
      nesting = 20
      generated_code = ''
      nesting.times do |i|
        generated_code << "def a#{i}() a#{i + 1}; end; "
      end
      generated_code << "def a#{nesting}() raise; end; a0\n"
      input = TestInputMethod.new([
        generated_code
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      if '2.5.0' <= RUBY_VERSION && RUBY_VERSION < '3.0.0' && STDOUT.tty?
        expected = [
          :*, /Traceback \(most recent call last\):\n/,
          :*, /\t... 5 levels...\n/,
          :*, /\t16: from \(irb\):1:in `a4'\n/,
          :*, /\t15: from \(irb\):1:in `a5'\n/,
          :*, /\t14: from \(irb\):1:in `a6'\n/,
          :*, /\t13: from \(irb\):1:in `a7'\n/,
          :*, /\t12: from \(irb\):1:in `a8'\n/,
          :*, /\t11: from \(irb\):1:in `a9'\n/,
          :*, /\t10: from \(irb\):1:in `a10'\n/,
          :*, /\t 9: from \(irb\):1:in `a11'\n/,
          :*, /\t 8: from \(irb\):1:in `a12'\n/,
          :*, /\t 7: from \(irb\):1:in `a13'\n/,
          :*, /\t 6: from \(irb\):1:in `a14'\n/,
          :*, /\t 5: from \(irb\):1:in `a15'\n/,
          :*, /\t 4: from \(irb\):1:in `a16'\n/,
          :*, /\t 3: from \(irb\):1:in `a17'\n/,
          :*, /\t 2: from \(irb\):1:in `a18'\n/,
          :*, /\t 1: from \(irb\):1:in `a19'\n/,
          :*, /\(irb\):1:in `a20': unhandled exception\n/,
        ]
      else
        expected = [
          :*, /\(irb\):1:in `a20': unhandled exception\n/,
          :*, /\tfrom \(irb\):1:in `a19'\n/,
          :*, /\tfrom \(irb\):1:in `a18'\n/,
          :*, /\tfrom \(irb\):1:in `a17'\n/,
          :*, /\tfrom \(irb\):1:in `a16'\n/,
          :*, /\tfrom \(irb\):1:in `a15'\n/,
          :*, /\tfrom \(irb\):1:in `a14'\n/,
          :*, /\tfrom \(irb\):1:in `a13'\n/,
          :*, /\tfrom \(irb\):1:in `a12'\n/,
          :*, /\tfrom \(irb\):1:in `a11'\n/,
          :*, /\tfrom \(irb\):1:in `a10'\n/,
          :*, /\tfrom \(irb\):1:in `a9'\n/,
          :*, /\tfrom \(irb\):1:in `a8'\n/,
          :*, /\tfrom \(irb\):1:in `a7'\n/,
          :*, /\tfrom \(irb\):1:in `a6'\n/,
          :*, /\tfrom \(irb\):1:in `a5'\n/,
          :*, /\tfrom \(irb\):1:in `a4'\n/,
          :*, /\t... 5 levels...\n/,
        ]
      end
      assert_pattern_list(expected, out)
    ensure
      $VERBOSE = verbose
    end

    def test_lineno
      input = TestInputMethod.new([
        "\n",
        "__LINE__\n",
        "__LINE__\n",
        "\n",
        "\n",
        "__LINE__\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_pattern_list([
          :*, /\b2\n/,
          :*, /\b3\n/,
          :*, /\b6\n/,
        ], out)
    end
  end
end
