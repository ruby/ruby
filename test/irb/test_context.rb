# frozen_string_literal: false
require 'tempfile'
require 'irb'

require_relative "helper"

module TestIRB
  class ContextTest < TestCase
    def setup
      IRB.init_config(nil)
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      IRB.conf[:USE_PAGER] = false
      workspace = IRB::WorkSpace.new(Object.new)
      @context = IRB::Context.new(nil, workspace, TestInputMethod.new)

      @get_screen_size = Reline.method(:get_screen_size)
      Reline.instance_eval { undef :get_screen_size }
      def Reline.get_screen_size
        [36, 80]
      end
      save_encodings
    end

    def teardown
      Reline.instance_eval { undef :get_screen_size }
      Reline.define_singleton_method(:get_screen_size, @get_screen_size)
      restore_encodings
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

      expected_output =
        if RUBY_3_4
          [
            :*, /\(irb\):1:in '<main>': Foo \(RuntimeError\)\n/,
            :*, /#<RuntimeError: Foo>\n/,
            :*, /0$/,
            :*, /0$/,
            /\s*/
          ]
        else
          [
            :*, /\(irb\):1:in `<main>': Foo \(RuntimeError\)\n/,
            :*, /#<RuntimeError: Foo>\n/,
            :*, /0$/,
            :*, /0$/,
            /\s*/
          ]
        end

      assert_pattern_list(expected_output, out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_raise2x
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
      expected_output =
        if RUBY_3_4
          [
            :*, /\(irb\):1:in '<main>': Foo \(RuntimeError\)\n/,
            :*, /\(irb\):2:in '<main>': Bar \(RuntimeError\)\n/,
            :*, /#<RuntimeError: Bar>\n/,
          ]
        else
          [
            :*, /\(irb\):1:in `<main>': Foo \(RuntimeError\)\n/,
            :*, /\(irb\):2:in `<main>': Bar \(RuntimeError\)\n/,
            :*, /#<RuntimeError: Bar>\n/,
          ]
        end
      assert_pattern_list(expected_output, out)
    end

    def test_prompt_n_deprecation
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), TestInputMethod.new)

      _, err = capture_output do
        irb.context.prompt_n = "foo"
        irb.context.prompt_n
      end

      assert_include err, "IRB::Context#prompt_n is deprecated"
      assert_include err, "IRB::Context#prompt_n= is deprecated"
    end

    def test_output_to_pipe
      require 'stringio'
      input = TestInputMethod.new(["n=1"])
      input.instance_variable_set(:@stdout, StringIO.new)
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.echo_on_assignment = :truncate
      irb.context.prompt_mode = :DEFAULT
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal "=> 1\n", out
    end

    {
      successful: [
        [false, "class Foo < Struct.new(:bar); end; Foo.new(123)\n", /#<struct bar=123>/],
        [:p, "class Foo < Struct.new(:bar); end; Foo.new(123)\n", /#<struct bar=123>/],
        [true, "class Foo < Struct.new(:bar); end; Foo.new(123)\n", /#<struct #<Class:.*>::Foo bar=123>/],
        [:yaml, "123", /--- 123\n/],
        [:marshal, "123", Marshal.dump(123)],
      ],
      failed: [
        [false, "BasicObject.new", /#<NoMethodError: undefined method (`|')to_s' for/],
        [:p, "class Foo; undef inspect ;end; Foo.new", /#<NoMethodError: undefined method (`|')inspect' for/],
        [:yaml, "BasicObject.new", /#<NoMethodError: undefined method (`|')inspect' for/],
        [:marshal, "[Object.new, Class.new]", /#<TypeError: can't dump anonymous class #<Class:/]
      ]
    }.each do |scenario, cases|
      cases.each do |inspect_mode, input, expected|
        define_method "test_#{inspect_mode}_inspect_mode_#{scenario}" do
          verbose, $VERBOSE = $VERBOSE, nil
          irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), TestInputMethod.new([input]))
          irb.context.inspect_mode = inspect_mode
          out, err = capture_output do
            irb.eval_input
          end
          assert_empty err
          assert_match(expected, out)
        ensure
          $VERBOSE = verbose
        end
      end
    end

    def test_object_inspection_handles_basic_object
      verbose, $VERBOSE = $VERBOSE, nil
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), TestInputMethod.new(["BasicObject.new"]))
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_not_match(/NoMethodError/, out)
      assert_match(/#<BasicObject:.*>/, out)
    ensure
      $VERBOSE = verbose
    end

    def test_object_inspection_falls_back_to_kernel_inspect_when_errored
      verbose, $VERBOSE = $VERBOSE, nil
      main = Object.new
      main.singleton_class.module_eval <<~RUBY
        class Foo
          def inspect
            raise "foo"
          end
        end
      RUBY

      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new(["Foo.new"]))
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/An error occurred when inspecting the object: #<RuntimeError: foo>/, out)
      assert_match(/Result of Kernel#inspect: #<#<Class:.*>::Foo:/, out)
    ensure
      $VERBOSE = verbose
    end

    def test_object_inspection_prints_useful_info_when_kernel_inspect_also_errored
      verbose, $VERBOSE = $VERBOSE, nil
      main = Object.new
      main.singleton_class.module_eval <<~RUBY
        class Foo
          def initialize
            # Kernel#inspect goes through instance variables with #inspect
            # So this will cause Kernel#inspect to fail
            @foo = BasicObject.new
          end

          def inspect
            raise "foo"
          end
        end
      RUBY

      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new(["Foo.new"]))
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/An error occurred when inspecting the object: #<RuntimeError: foo>/, out)
      assert_match(/An error occurred when running Kernel#inspect: #<NoMethodError: undefined method (`|')inspect' for/, out)
    ensure
      $VERBOSE = verbose
    end

    def test_default_config
      assert_equal(true, @context.use_autocomplete?)
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
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> 1\n=> 2\n=> 3\n=> 4\n", out)

      # Everything is output, like before echo_on_assignment was introduced
      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = true
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> 1\n=> 1\n=> [2, 3]\n=> 2\n=> 3\n=> 4\n=> 4\n", out)

      # Nothing is output when echo is false
      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = false
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      # Nothing is output when echo is false even if echo_on_assignment is true
      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = true
      out, err = capture_output do
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
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = :truncate
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect[0..3]}...\n=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = true
      irb.context.echo_on_assignment = true
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("=> \n#{value.pretty_inspect}=> \n#{value.pretty_inspect}", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = false
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = :truncate
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)

      input.reset
      irb.context.echo = false
      irb.context.echo_on_assignment = true
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("", out)
    end

    def test_omit_multiline_on_assignment
      without_colorize do
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
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("=> \n#{value}\n", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)

        input.reset
        irb.context.echo = true
        irb.context.echo_on_assignment = :truncate
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("=> #{value_first_line[0..(input.winsize.last - 9)]}...\n=> \n#{value}\n", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)

        input.reset
        irb.context.echo = true
        irb.context.echo_on_assignment = true
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("=> \n#{value}\n=> \n#{value}\n", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)

        input.reset
        irb.context.echo = false
        irb.context.echo_on_assignment = false
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)

        input.reset
        irb.context.echo = false
        irb.context.echo_on_assignment = :truncate
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)

        input.reset
        irb.context.echo = false
        irb.context.echo_on_assignment = true
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("", out)
        irb.context.evaluate_expression('A.remove_method(:inspect)', 0)
      end
    end

    def test_echo_on_assignment_conf
      # Default
      IRB.conf[:ECHO] = nil
      IRB.conf[:ECHO_ON_ASSIGNMENT] = nil
      without_colorize do
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
    end

    def test_multiline_output_on_default_inspector
      main = Object.new
      def main.inspect
        "abc\ndef"
      end

      without_colorize do
        input = TestInputMethod.new([
          "self"
        ])
        irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
        irb.context.return_format = "=> %s\n"

        # The default
        irb.context.newline_before_multiline_output = true
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("=> \nabc\ndef\n",
                     out)

        # No newline before multiline output
        input.reset
        irb.context.newline_before_multiline_output = false
        out, err = capture_output do
          irb.eval_input
        end
        assert_empty err
        assert_equal("=> abc\ndef\n", out)
      end
    end

    def test_default_return_format
      IRB.conf[:PROMPT][:MY_PROMPT] = {
        :PROMPT_I => "%03n> ",
        :PROMPT_S => "%03n> ",
        :PROMPT_C => "%03n> "
        # without :RETURN
        # :RETURN => "%s\n"
      }
      IRB.conf[:PROMPT_MODE] = :MY_PROMPT
      input = TestInputMethod.new([
        "3"
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_equal("3\n",
                   out)
    end

    def test_eval_input_with_exception
      pend if RUBY_ENGINE == 'truffleruby'
      verbose, $VERBOSE = $VERBOSE, nil
      input = TestInputMethod.new([
        "def hoge() fuga; end; def fuga() raise; end; hoge\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      expected_output =
        if RUBY_3_4
          [
            :*, /\(irb\):1:in 'fuga': unhandled exception\n/,
            :*, /\tfrom \(irb\):1:in 'hoge'\n/,
            :*, /\tfrom \(irb\):1:in '<main>'\n/,
            :*
          ]
        elsif RUBY_VERSION < '3.0.0' && STDOUT.tty?
          [
            :*, /Traceback \(most recent call last\):\n/,
            :*, /\t 2: from \(irb\):1:in `<main>'\n/,
            :*, /\t 1: from \(irb\):1:in `hoge'\n/,
            :*, /\(irb\):1:in `fuga': unhandled exception\n/,
          ]
        else
          [
            :*, /\(irb\):1:in `fuga': unhandled exception\n/,
            :*, /\tfrom \(irb\):1:in `hoge'\n/,
            :*, /\tfrom \(irb\):1:in `<main>'\n/,
            :*
          ]
        end
      assert_pattern_list(expected_output, out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_with_invalid_byte_sequence_exception
      verbose, $VERBOSE = $VERBOSE, nil
      input = TestInputMethod.new([
        %Q{def hoge() fuga; end; def fuga() raise "A\\xF3B"; end; hoge\n},
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      expected_output =
        if RUBY_3_4
          [
            :*, /\(irb\):1:in 'fuga': A\\xF3B \(RuntimeError\)\n/,
            :*, /\tfrom \(irb\):1:in 'hoge'\n/,
            :*, /\tfrom \(irb\):1:in '<main>'\n/,
            :*
          ]
        elsif RUBY_VERSION < '3.0.0' && STDOUT.tty?
          [
            :*, /Traceback \(most recent call last\):\n/,
            :*, /\t 2: from \(irb\):1:in `<main>'\n/,
            :*, /\t 1: from \(irb\):1:in `hoge'\n/,
            :*, /\(irb\):1:in `fuga': A\\xF3B \(RuntimeError\)\n/,
          ]
        else
          [
            :*, /\(irb\):1:in `fuga': A\\xF3B \(RuntimeError\)\n/,
            :*, /\tfrom \(irb\):1:in `hoge'\n/,
            :*, /\tfrom \(irb\):1:in `<main>'\n/,
            :*
          ]
        end

      assert_pattern_list(expected_output, out)
    ensure
      $VERBOSE = verbose
    end

    def test_eval_input_with_long_exception
      pend if RUBY_ENGINE == 'truffleruby'
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
      if RUBY_VERSION < '3.0.0' && STDOUT.tty?
        expected = [
          :*, /Traceback \(most recent call last\):\n/,
          :*, /\t... \d+ levels...\n/,
          :*, /\t16: from \(irb\):1:in (`|')a4'\n/,
          :*, /\t15: from \(irb\):1:in (`|')a5'\n/,
          :*, /\t14: from \(irb\):1:in (`|')a6'\n/,
          :*, /\t13: from \(irb\):1:in (`|')a7'\n/,
          :*, /\t12: from \(irb\):1:in (`|')a8'\n/,
          :*, /\t11: from \(irb\):1:in (`|')a9'\n/,
          :*, /\t10: from \(irb\):1:in (`|')a10'\n/,
          :*, /\t 9: from \(irb\):1:in (`|')a11'\n/,
          :*, /\t 8: from \(irb\):1:in (`|')a12'\n/,
          :*, /\t 7: from \(irb\):1:in (`|')a13'\n/,
          :*, /\t 6: from \(irb\):1:in (`|')a14'\n/,
          :*, /\t 5: from \(irb\):1:in (`|')a15'\n/,
          :*, /\t 4: from \(irb\):1:in (`|')a16'\n/,
          :*, /\t 3: from \(irb\):1:in (`|')a17'\n/,
          :*, /\t 2: from \(irb\):1:in (`|')a18'\n/,
          :*, /\t 1: from \(irb\):1:in (`|')a19'\n/,
          :*, /\(irb\):1:in (`|')a20': unhandled exception\n/,
        ]
      else
        expected = [
          :*, /\(irb\):1:in (`|')a20': unhandled exception\n/,
          :*, /\tfrom \(irb\):1:in (`|')a19'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a18'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a17'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a16'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a15'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a14'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a13'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a12'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a11'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a10'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a9'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a8'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a7'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a6'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a5'\n/,
          :*, /\tfrom \(irb\):1:in (`|')a4'\n/,
          :*, /\t... \d+ levels...\n/,
        ]
      end
      assert_pattern_list(expected, out)
    ensure
      $VERBOSE = verbose
    end

    def test_prompt_main_escape
      main = Struct.new(:to_s).new("main\a\t\r\n")
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_equal("irb(main    )>", irb.send(:format_prompt, 'irb(%m)>', nil, 1, 1))
    end

    def test_prompt_main_inspect_escape
      main = Struct.new(:inspect).new("main\\n\nmain")
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_equal("irb(main\\n main)>", irb.send(:format_prompt, 'irb(%M)>', nil, 1, 1))
    end

    def test_prompt_main_truncate
      main = Struct.new(:to_s).new("a" * 100)
      def main.inspect; to_s.inspect; end
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_equal('irb(aaaaaaaaaaaaaaaaaaaaaaaaaaaaa...)>', irb.send(:format_prompt, 'irb(%m)>', nil, 1, 1))
      assert_equal('irb("aaaaaaaaaaaaaaaaaaaaaaaaaaaa...)>', irb.send(:format_prompt, 'irb(%M)>', nil, 1, 1))
    end

    def test_prompt_main_basic_object
      main = BasicObject.new
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_match(/irb\(#<BasicObject:.+\)/, irb.send(:format_prompt, 'irb(%m)>', nil, 1, 1))
      assert_match(/irb\(#<BasicObject:.+\)/, irb.send(:format_prompt, 'irb(%M)>', nil, 1, 1))
    end

    def test_prompt_main_raise
      main = Object.new
      def main.to_s; raise TypeError; end
      def main.inspect; raise ArgumentError; end
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_equal("irb(!TypeError)>", irb.send(:format_prompt, 'irb(%m)>', nil, 1, 1))
      assert_equal("irb(!ArgumentError)>", irb.send(:format_prompt, 'irb(%M)>', nil, 1, 1))
    end

    def test_prompt_format
      main = 'main'
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), TestInputMethod.new)
      assert_equal('%% main %m %main %%m >', irb.send(:format_prompt, '%%%% %m %%m %%%m %%%%m %l', '>', 1, 1))
      assert_equal('42,%i, 42,%3i,042,%03i', irb.send(:format_prompt, '%i,%%i,%3i,%%3i,%03i,%%03i', nil, 42, 1))
      assert_equal('42,%n, 42,%3n,042,%03n', irb.send(:format_prompt, '%n,%%n,%3n,%%3n,%03n,%%03n', nil, 1, 42))
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

    def test_irb_path_setter
      @context.irb_path = __FILE__
      assert_equal(__FILE__, @context.irb_path)
      assert_equal("#{__FILE__}(irb)", @context.instance_variable_get(:@eval_path))
      @context.irb_path = 'file/does/not/exist'
      assert_equal('file/does/not/exist', @context.irb_path)
      assert_equal('file/does/not/exist', @context.instance_variable_get(:@eval_path))
      @context.irb_path = "#{__FILE__}(irb)"
      assert_equal("#{__FILE__}(irb)", @context.irb_path)
      assert_equal("#{__FILE__}(irb)", @context.instance_variable_get(:@eval_path))
    end

    def test_build_completor
      verbose, $VERBOSE = $VERBOSE, nil
      original_completor = IRB.conf[:COMPLETOR]
      IRB.conf[:COMPLETOR] = nil
      assert_match(/IRB::(Regexp|Type)Completor/, @context.send(:build_completor).class.name)
      IRB.conf[:COMPLETOR] = :regexp
      assert_equal 'IRB::RegexpCompletor', @context.send(:build_completor).class.name
      IRB.conf[:COMPLETOR] = :unknown
      assert_equal 'IRB::RegexpCompletor', @context.send(:build_completor).class.name
      # :type is tested in test_type_completor.rb
    ensure
      $VERBOSE = verbose
      IRB.conf[:COMPLETOR] = original_completor
    end

    private

    def without_colorize
      original_value = IRB.conf[:USE_COLORIZE]
      IRB.conf[:USE_COLORIZE] = false
      yield
    ensure
      IRB.conf[:USE_COLORIZE] = original_value
    end
  end
end
