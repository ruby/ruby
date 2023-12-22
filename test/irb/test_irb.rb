# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class InputTest < IntegrationTestCase
    def test_symbol_aliases_are_handled_correctly
      write_ruby <<~'RUBY'
        class Foo
        end
        binding.irb
      RUBY

      output = run_ruby_file do
        type "$ Foo"
        type "exit!"
      end

      assert_include output, "From: #{@ruby_file.path}:1"
    end

    def test_symbol_aliases_are_handled_correctly_with_singleline_mode
      write_rc <<~RUBY
        IRB.conf[:USE_SINGLELINE] = true
      RUBY

      write_ruby <<~'RUBY'
        class Foo
        end
        binding.irb
      RUBY

      output = run_ruby_file do
        type "irb_info"
        type "$ Foo"
        type "exit!"
      end

      # Make sure it's tested in singleline mode
      assert_include output, "InputMethod: ReadlineInputMethod"
      assert_include output, "From: #{@ruby_file.path}:1"
    end

    def test_symbol_aliases_dont_affect_ruby_syntax
      write_ruby <<~'RUBY'
        $foo = "It's a foo"
        @bar = "It's a bar"
        binding.irb
      RUBY

      output = run_ruby_file do
        type "$foo"
        type "@bar"
        type "exit!"
      end

      assert_include output, "=> \"It's a foo\""
      assert_include output, "=> \"It's a bar\""
    end
  end

  class IrbIOConfigurationTest < TestCase
    Row = Struct.new(:content, :current_line_spaces, :new_line_spaces, :indent_level)

    class MockIO_AutoIndent
      attr_reader :calculated_indent

      def initialize(*params)
        @params = params
      end

      def auto_indent(&block)
        @calculated_indent = block.call(*@params)
      end
    end

    class MockIO_DynamicPrompt
      attr_reader :prompt_list

      def initialize(params, &assertion)
        @params = params
      end

      def dynamic_prompt(&block)
        @prompt_list = block.call(@params)
      end
    end

    def setup
      save_encodings
      @irb = build_irb
    end

    def teardown
      restore_encodings
    end

    class AutoIndentationTest < IrbIOConfigurationTest
      def test_auto_indent
        input_with_correct_indents = [
          [%q(def each_top_level_statement), 0, 2],
          [%q(  initialize_input), 2, 2],
          [%q(  catch(:TERM_INPUT) do), 2, 4],
          [%q(    loop do), 4, 6],
          [%q(      begin), 6, 8],
          [%q(        prompt), 8, 8],
          [%q(        unless l = lex), 8, 10],
          [%q(          throw :TERM_INPUT if @line == ''), 10, 10],
          [%q(        else), 8, 10],
          [%q(          @line_no += l.count("\n")), 10, 10],
          [%q(          next if l == "\n"), 10, 10],
          [%q(          @line.concat l), 10, 10],
          [%q(          if @code_block_open or @ltype or @continue or @indent > 0), 10, 12],
          [%q(            next), 12, 12],
          [%q(          end), 10, 10],
          [%q(        end), 8, 8],
          [%q(        if @line != "\n"), 8, 10],
          [%q(          @line.force_encoding(@io.encoding)), 10, 10],
          [%q(          yield @line, @exp_line_no), 10, 10],
          [%q(        end), 8, 8],
          [%q(        break if @io.eof?), 8, 8],
          [%q(        @line = ''), 8, 8],
          [%q(        @exp_line_no = @line_no), 8, 8],
          [%q(        ), nil, 8],
          [%q(        @indent = 0), 8, 8],
          [%q(      rescue TerminateLineInput), 6, 8],
          [%q(        initialize_input), 8, 8],
          [%q(        prompt), 8, 8],
          [%q(      end), 6, 6],
          [%q(    end), 4, 4],
          [%q(  end), 2, 2],
          [%q(end), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_braces_on_their_own_line
        input_with_correct_indents = [
          [%q(if true), 0, 2],
          [%q(  [), 2, 4],
          [%q(  ]), 2, 2],
          [%q(end), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_multiple_braces_in_a_line
        input_with_correct_indents = [
          [%q([[[), 0, 6],
          [%q(    ]), 4, 4],
          [%q(  ]), 2, 2],
          [%q(]), 0, 0],
          [%q([<<FOO]), 0, 0],
          [%q(hello), 0, 0],
          [%q(FOO), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_a_closed_brace_and_not_closed_brace_in_a_line
        input_with_correct_indents = [
          [%q(p() {), 0, 2],
          [%q(}), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_symbols
        input_with_correct_indents = [
          [%q(:a), 0, 0],
          [%q(:A), 0, 0],
          [%q(:+), 0, 0],
          [%q(:@@a), 0, 0],
          [%q(:@a), 0, 0],
          [%q(:$a), 0, 0],
          [%q(:def), 0, 0],
          [%q(:`), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_incomplete_coding_magic_comment
        input_with_correct_indents = [
          [%q(#coding:u), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_incomplete_encoding_magic_comment
        input_with_correct_indents = [
          [%q(#encoding:u), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_incomplete_emacs_coding_magic_comment
        input_with_correct_indents = [
          [%q(# -*- coding: u), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_incomplete_vim_coding_magic_comment
        input_with_correct_indents = [
          [%q(# vim:set fileencoding=u), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_mixed_rescue
        input_with_correct_indents = [
          [%q(def m), 0, 2],
          [%q(  begin), 2, 4],
          [%q(    begin), 4, 6],
          [%q(      x = a rescue 4), 6, 6],
          [%q(      y = [(a rescue 5)]), 6, 6],
          [%q(      [x, y]), 6, 6],
          [%q(    rescue => e), 4, 6],
          [%q(      raise e rescue 8), 6, 6],
          [%q(    end), 4, 4],
          [%q(  rescue), 2, 4],
          [%q(    raise rescue 11), 4, 4],
          [%q(  end), 2, 2],
          [%q(rescue => e), 0, 2],
          [%q(  raise e rescue 14), 2, 2],
          [%q(end), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_oneliner_method_definition
        input_with_correct_indents = [
          [%q(class A), 0, 2],
          [%q(  def foo0), 2, 4],
          [%q(    3), 4, 4],
          [%q(  end), 2, 2],
          [%q(  def foo1()), 2, 4],
          [%q(    3), 4, 4],
          [%q(  end), 2, 2],
          [%q(  def foo2(a, b)), 2, 4],
          [%q(    a + b), 4, 4],
          [%q(  end), 2, 2],
          [%q(  def foo3 a, b), 2, 4],
          [%q(    a + b), 4, 4],
          [%q(  end), 2, 2],
          [%q(  def bar0() = 3), 2, 2],
          [%q(  def bar1(a) = a), 2, 2],
          [%q(  def bar2(a, b) = a + b), 2, 2],
          [%q(  def bar3() = :s), 2, 2],
          [%q(  def bar4() = Time.now), 2, 2],
          [%q(end), 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents)
      end

      def test_tlambda
        input_with_correct_indents = [
          [%q(if true), 0, 2, 1],
          [%q(  -> {), 2, 4, 2],
          [%q(  }), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_corresponding_syntax_to_keyword_do_in_class
        input_with_correct_indents = [
          [%q(class C), 0, 2, 1],
          [%q(  while method_name do), 2, 4, 2],
          [%q(    3), 4, 4, 2],
          [%q(  end), 2, 2, 1],
          [%q(  foo do), 2, 4, 2],
          [%q(    3), 4, 4, 2],
          [%q(  end), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_corresponding_syntax_to_keyword_do
        input_with_correct_indents = [
          [%q(while i > 0), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while true), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while ->{i > 0}.call), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while ->{true}.call), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while i > 0 do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while true do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while ->{i > 0}.call do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(while ->{true}.call do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(foo do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(foo true do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(foo ->{true} do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(foo ->{i > 0} do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_corresponding_syntax_to_keyword_for
        input_with_correct_indents = [
          [%q(for i in [1]), 0, 2, 1],
          [%q(  puts i), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_corresponding_syntax_to_keyword_for_with_do
        input_with_correct_indents = [
          [%q(for i in [1] do), 0, 2, 1],
          [%q(  puts i), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_typing_incomplete_include_interpreted_as_keyword_in
        input_with_correct_indents = [
          [%q(module E), 0, 2, 1],
          [%q(end), 0, 0, 0],
          [%q(class A), 0, 2, 1],
          [%q(  in), 2, 2, 1] # scenario typing `include E`
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)

      end

      def test_bracket_corresponding_to_times
        input_with_correct_indents = [
          [%q(3.times { |i|), 0, 2, 1],
          [%q(  puts i), 2, 2, 1],
          [%q(}), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_do_corresponding_to_times
        input_with_correct_indents = [
          [%q(3.times do |i|), 0, 2, 1],
          [%q(  puts i), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_bracket_corresponding_to_loop
        input_with_correct_indents = [
          ['loop {', 0, 2, 1],
          ['  3', 2, 2, 1],
          ['}', 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_do_corresponding_to_loop
        input_with_correct_indents = [
          [%q(loop do), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_embdoc_indent
        input_with_correct_indents = [
          [%q(=begin), 0, 0, 0],
          [%q(a), 0, 0, 0],
          [%q( b), 1, 1, 0],
          [%q(=end), 0, 0, 0],
          [%q(if 1), 0, 2, 1],
          [%q(  2), 2, 2, 1],
          [%q(=begin), 0, 0, 0],
          [%q(a), 0, 0, 0],
          [%q( b), 1, 1, 0],
          [%q(=end), 0, 2, 1],
          [%q(  3), 2, 2, 1],
          [%q(end), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_heredoc_with_indent
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
          pend 'This test needs Ripper::Lexer#scan to take broken tokens'
        end
        input_with_correct_indents = [
          [%q(<<~Q+<<~R), 0, 2, 1],
          [%q(a), 2, 2, 1],
          [%q(a), 2, 2, 1],
          [%q(  b), 2, 2, 1],
          [%q(  b), 2, 2, 1],
          [%q(  Q), 0, 2, 1],
          [%q(    c), 4, 4, 1],
          [%q(    c), 4, 4, 1],
          [%q(    R), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_oneliner_def_in_multiple_lines
        input_with_correct_indents = [
          [%q(def a()=[), 0, 2, 1],
          [%q(  1,), 2, 2, 1],
          [%q(].), 0, 0, 0],
          [%q(to_s), 0, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_broken_heredoc
        input_with_correct_indents = [
          [%q(def foo), 0, 2, 1],
          [%q(  <<~Q), 2, 4, 2],
          [%q(  Qend), 4, 4, 2],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_pasted_code_keep_base_indent_spaces
        input_with_correct_indents = [
          [%q(    def foo), 0, 6, 1],
          [%q(        if bar), 6, 10, 2],
          [%q(          [1), 10, 12, 3],
          [%q(          ]+[["a), 10, 14, 4],
          [%q(b" + `c), 0, 14, 4],
          [%q(d` + /e), 0, 14, 4],
          [%q(f/ + :"g), 0, 14, 4],
          [%q(h".tap do), 0, 16, 5],
          [%q(                1), 16, 16, 5],
          [%q(              end), 14, 14, 4],
          [%q(            ]), 12, 12, 3],
          [%q(          ]), 10, 10, 2],
          [%q(        end), 8, 6, 1],
          [%q(    end), 4, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_pasted_code_keep_base_indent_spaces_with_heredoc
        input_with_correct_indents = [
          [%q(    def foo), 0, 6, 1],
          [%q(        if bar), 6, 10, 2],
          [%q(          [1), 10, 12, 3],
          [%q(          ]+[["a), 10, 14, 4],
          [%q(b" + <<~A + <<-B + <<C), 0, 16, 5],
          [%q(                a#{), 16, 18, 6],
          [%q(                1), 18, 18, 6],
          [%q(                }), 16, 16, 5],
          [%q(              A), 14, 16, 5],
          [%q(                b#{), 16, 18, 6],
          [%q(                1), 18, 18, 6],
          [%q(                }), 16, 16, 5],
          [%q(              B), 14, 0, 0],
          [%q(c#{), 0, 2, 1],
          [%q(1), 2, 2, 1],
          [%q(}), 0, 0, 0],
          [%q(C), 0, 14, 4],
          [%q(            ]), 12, 12, 3],
          [%q(          ]), 10, 10, 2],
          [%q(        end), 8, 6, 1],
          [%q(    end), 4, 0, 0],
        ]

        assert_rows_with_correct_indents(input_with_correct_indents, assert_indent_level: true)
      end

      def test_heredoc_keep_indent_spaces
        (1..4).each do |indent|
          row = Row.new(' ' * indent, nil, [4, indent].max, 2)
          lines = ['def foo', '  <<~Q', row.content]
          assert_row_indenting(lines, row)
          assert_indent_level(lines, row.indent_level)
        end
      end

      private

      def assert_row_indenting(lines, row)
        actual_current_line_spaces = calculate_indenting(lines, false)

        error_message = <<~MSG
          Incorrect spaces calculation for line:

          ```
        > #{lines.last}
          ```

          All lines:

          ```
          #{lines.join("\n")}
          ```
        MSG
        assert_equal(row.current_line_spaces, actual_current_line_spaces, error_message)

        error_message = <<~MSG
          Incorrect spaces calculation for line after the current line:

          ```
          #{lines.last}
        >
          ```

          All lines:

          ```
          #{lines.join("\n")}
          ```
        MSG
        actual_next_line_spaces = calculate_indenting(lines, true)
        assert_equal(row.new_line_spaces, actual_next_line_spaces, error_message)
      end

      def assert_rows_with_correct_indents(rows_with_spaces, assert_indent_level: false)
        lines = []
        rows_with_spaces.map do |row|
          row = Row.new(*row)
          lines << row.content
          assert_row_indenting(lines, row)

          if assert_indent_level
            assert_indent_level(lines, row.indent_level)
          end
        end
      end

      def assert_indent_level(lines, expected)
        code = lines.map { |l| "#{l}\n" }.join # code should end with "\n"
        _tokens, opens, _ = @irb.scanner.check_code_state(code, local_variables: [])
        indent_level = @irb.scanner.calc_indent_level(opens)
        error_message = "Calculated the wrong number of indent level for:\n #{lines.join("\n")}"
        assert_equal(expected, indent_level, error_message)
      end

      def calculate_indenting(lines, add_new_line)
        lines = lines + [""] if add_new_line
        last_line_index = lines.length - 1
        byte_pointer = lines.last.length

        mock_io = MockIO_AutoIndent.new(lines, last_line_index, byte_pointer, add_new_line)
        @irb.context.auto_indent_mode = true
        @irb.context.io = mock_io
        @irb.configure_io

        mock_io.calculated_indent
      end
    end

    class DynamicPromptTest < IrbIOConfigurationTest
      def test_endless_range_at_end_of_line
        input_with_prompt = [
          ['001:0: :> ', %q(a = 3..)],
          ['002:0: :> ', %q()],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_heredoc_with_embexpr
        input_with_prompt = [
          ['001:0:":* ', %q(<<A+%W[#{<<B)],
          ['002:0:":* ', %q(#{<<C+%W[)],
          ['003:0:":* ', %q(a)],
          ['004:2:]:* ', %q(C)],
          ['005:2:]:* ', %q(a)],
          ['006:0:":* ', %q(]})],
          ['007:0:":* ', %q(})],
          ['008:0:":* ', %q(A)],
          ['009:2:]:* ', %q(B)],
          ['010:1:]:* ', %q(})],
          ['011:0: :> ', %q(])],
          ['012:0: :> ', %q()],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_heredoc_prompt_with_quotes
        input_with_prompt = [
          ["001:1:':* ", %q(<<~'A')],
          ["002:1:':* ", %q(#{foobar})],
          ["003:0: :> ", %q(A)],
          ["004:1:`:* ", %q(<<~`A`)],
          ["005:1:`:* ", %q(whoami)],
          ["006:0: :> ", %q(A)],
          ['007:1:":* ', %q(<<~"A")],
          ['008:1:":* ', %q(foobar)],
          ['009:0: :> ', %q(A)],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_backtick_method
        input_with_prompt = [
          ['001:0: :> ', %q(self.`(arg))],
          ['002:0: :> ', %q()],
          ['003:0: :> ', %q(def `(); end)],
          ['004:0: :> ', %q()],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_dynamic_prompt
        input_with_prompt = [
          ['001:1: :* ', %q(def hoge)],
          ['002:1: :* ', %q(  3)],
          ['003:0: :> ', %q(end)],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_dynamic_prompt_with_double_newline_breaking_code
        input_with_prompt = [
          ['001:1: :* ', %q(if true)],
          ['002:2: :* ', %q(%)],
          ['003:1: :* ', %q(;end)],
          ['004:1: :* ', %q(;hello)],
          ['005:0: :> ', %q(end)],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_dynamic_prompt_with_multiline_literal
        input_with_prompt = [
          ['001:1: :* ', %q(if true)],
          ['002:2:]:* ', %q(  %w[)],
          ['003:2:]:* ', %q(  a)],
          ['004:1: :* ', %q(  ])],
          ['005:1: :* ', %q(  b)],
          ['006:2:]:* ', %q(  %w[)],
          ['007:2:]:* ', %q(  c)],
          ['008:1: :* ', %q(  ])],
          ['009:0: :> ', %q(end)],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def test_dynamic_prompt_with_blank_line
        input_with_prompt = [
          ['001:1:]:* ', %q(%w[)],
          ['002:1:]:* ', %q()],
          ['003:0: :> ', %q(])],
        ]

        assert_dynamic_prompt(input_with_prompt)
      end

      def assert_dynamic_prompt(input_with_prompt)
        expected_prompt_list, lines = input_with_prompt.transpose
        def @irb.generate_prompt(opens, continue, line_offset)
          ltype = @scanner.ltype_from_open_tokens(opens)
          indent = @scanner.calc_indent_level(opens)
          continue = opens.any? || continue
          line_no = @line_no + line_offset
          '%03d:%01d:%1s:%s ' % [line_no, indent, ltype, continue ? '*' : '>']
        end
        io = MockIO_DynamicPrompt.new(lines)
        @irb.context.io = io
        @irb.configure_io

        error_message = <<~EOM
          Expected dynamic prompt:
          #{expected_prompt_list.join("\n")}

          Actual dynamic prompt:
          #{io.prompt_list.join("\n")}
        EOM
        assert_equal(expected_prompt_list, io.prompt_list, error_message)
      end
    end

    private

    def build_binding
      Object.new.instance_eval { binding }
    end

    def build_irb
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(build_binding)

      IRB.conf[:VERBOSE] = false
      IRB::Irb.new(workspace, TestInputMethod.new)
    end
  end
end
