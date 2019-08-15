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
    end

    def setup
      IRB.init_config(nil)
      IRB.conf[:USE_READLINE] = false
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(Object.new)
      @context = IRB::Context.new(nil, workspace, TestInputMethod.new)
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

    def test_eval_input
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
      assert_pattern_list([:*, /RuntimeError \(.*Foo.*\).*\n/,
                           :*, /#<RuntimeError: Foo>\n/,
                           :*, /0$/,
                           :*, /0$/,
                           /\s*/], out)
    ensure
      $VERBOSE = verbose
    end

    def test_default_config
      assert_equal(true, @context.use_colorize?)
    end
  end
end
