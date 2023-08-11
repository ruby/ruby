$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'irb'
require 'rubygems'
require 'ostruct'

require_relative "helper"

module TestIRB
  class RubyLexTest < TestCase
    Row = Struct.new(:content, :current_line_spaces, :new_line_spaces, :indent_level)

    class MockIO_AutoIndent
      attr_reader :calculated_indent

      def initialize(*params)
        @params = params
        @calculated_indent
      end

      def auto_indent(&block)
        @calculated_indent = block.call(*@params)
      end
    end

    def setup
      save_encodings
    end

    def teardown
      restore_encodings
    end

    def calculate_indenting(lines, add_new_line)
      lines = lines + [""] if add_new_line
      last_line_index = lines.length - 1
      byte_pointer = lines.last.length

      context = build_context
      context.auto_indent_mode = true

      ruby_lex = RubyLex.new(context)
      mock_io = MockIO_AutoIndent.new(lines, last_line_index, byte_pointer, add_new_line)

      ruby_lex.configure_io(mock_io)
      mock_io.calculated_indent
    end

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

    def assert_indent_level(lines, expected, local_variables: [])
      indent_level, _continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Calculated the wrong number of indent level for:\n #{lines.join("\n")}"
      assert_equal(expected, indent_level, error_message)
    end

    def assert_should_continue(lines, expected, local_variables: [])
      _indent_level, continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of should_continue for:\n #{lines.join("\n")}"
      assert_equal(expected, continue, error_message)
    end

    def assert_code_block_open(lines, expected, local_variables: [])
      _indent_level, _continue, code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of code_block_open for:\n #{lines.join("\n")}"
      assert_equal(expected, code_block_open, error_message)
    end

    def check_state(lines, local_variables: [])
      context = build_context(local_variables)
      code = lines.map { |l| "#{l}\n" }.join # code should end with "\n"
      ruby_lex = RubyLex.new(context)
      tokens, opens, terminated = ruby_lex.check_code_state(code)
      indent_level = ruby_lex.calc_indent_level(opens)
      continue = ruby_lex.should_continue?(tokens)
      [indent_level, continue, !terminated]
    end

    def test_interpolate_token_with_heredoc_and_unclosed_embexpr
      code = <<~'EOC'
        ①+<<A-②
        #{③*<<B/④
        #{⑤&<<C|⑥
      EOC
      ripper_tokens = Ripper.tokenize(code)
      rubylex_tokens = RubyLex.ripper_lex_without_warning(code)
      # Assert no missing part
      assert_equal(code, rubylex_tokens.map(&:tok).join)
      # Assert ripper tokens are not removed
      ripper_tokens.each do |tok|
        assert(rubylex_tokens.any? { |t| t.tok == tok && t.tok != :on_ignored_by_ripper })
      end
      # Assert interpolated token position
      rubylex_tokens.each do |t|
        row, col = t.pos
        assert_equal t.tok, code.lines[row - 1].byteslice(col, t.tok.bytesize)
      end
    end

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

    def test_local_variables_dependent_code
      lines = ["a /1#/ do", "2"]
      assert_indent_level(lines, 1)
      assert_code_block_open(lines, true)
      assert_indent_level(lines, 0, local_variables: ['a'])
      assert_code_block_open(lines, false, local_variables: ['a'])
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

    def test_heredoc_keep_indent_spaces
      (1..4).each do |indent|
        row = Row.new(' ' * indent, nil, [4, indent].max, 2)
        lines = ['def foo', '  <<~Q', row.content]
        assert_row_indenting(lines, row)
        assert_indent_level(lines, row.indent_level)
      end
    end

    class MockIO_DynamicPrompt
      def initialize(params, &assertion)
        @params = params
        @assertion = assertion
      end

      def dynamic_prompt(&block)
        result = block.call(@params)
        @assertion.call(result)
      end
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

    def assert_dynamic_prompt(input_with_prompt)
      expected_prompt_list, lines = input_with_prompt.transpose
      context = build_context
      ruby_lex = RubyLex.new(context)
      dynamic_prompt_executed = false
      io = MockIO_DynamicPrompt.new(lines) do |prompt_list|
        error_message = <<~EOM
          Expected dynamic prompt:
          #{expected_prompt_list.join("\n")}

          Actual dynamic prompt:
          #{prompt_list.join("\n")}
        EOM
        dynamic_prompt_executed = true
        assert_equal(expected_prompt_list, prompt_list, error_message)
      end
      ruby_lex.set_prompt do |ltype, indent, continue, line_no|
        '%03d:%01d:%1s:%s ' % [line_no, indent, ltype, continue ? '*' : '>']
      end
      ruby_lex.configure_io(io)
      assert dynamic_prompt_executed, "dynamic_prompt's assertions were not executed."
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

    def test_literal_ends_with_space
      assert_code_block_open(['% a'], true)
      assert_code_block_open(['% a '], false)
    end

    def test_literal_ends_with_newline
      assert_code_block_open(['%'], true)
      assert_code_block_open(['%', ''], false)
    end

    def test_should_continue
      assert_should_continue(['a'], false)
      assert_should_continue(['/a/'], false)
      assert_should_continue(['a;'], false)
      assert_should_continue(['<<A', 'A'], false)
      assert_should_continue(['a...'], false)
      assert_should_continue(['a\\'], true)
      assert_should_continue(['a.'], true)
      assert_should_continue(['a+'], true)
      assert_should_continue(['a; #comment', '', '=begin', 'embdoc', '=end', ''], false)
      assert_should_continue(['a+ #comment', '', '=begin', 'embdoc', '=end', ''], true)
    end

    def test_code_block_open_with_should_continue
      # syntax ok
      assert_code_block_open(['a'], false) # continue: false
      assert_code_block_open(['a\\'], true) # continue: true

      # recoverable syntax error code is not terminated
      assert_code_block_open(['a+'], true)

      # unrecoverable syntax error code is terminated
      assert_code_block_open(['.; a+'], false)

      # other syntax error that failed to determine if it is recoverable or not
      assert_code_block_open(['@; a'], false)
      assert_code_block_open(['@; a+'], true)
      assert_code_block_open(['@; (a'], true)
    end

    def test_broken_percent_literal
      tokens = RubyLex.ripper_lex_without_warning('%wwww')
      pos_to_index = {}
      tokens.each_with_index { |t, i|
        assert_nil(pos_to_index[t.pos], "There is already another token in the position of #{t.inspect}.")
        pos_to_index[t.pos] = i
      }
    end

    def test_broken_percent_literal_in_method
      tokens = RubyLex.ripper_lex_without_warning(<<~EOC.chomp)
        def foo
          %wwww
        end
      EOC
      pos_to_index = {}
      tokens.each_with_index { |t, i|
        assert_nil(pos_to_index[t.pos], "There is already another token in the position of #{t.inspect}.")
        pos_to_index[t.pos] = i
      }
    end

    def test_unterminated_code
      ['do', '<<A'].each do |code|
        tokens = RubyLex.ripper_lex_without_warning(code)
        assert_equal(code, tokens.map(&:tok).join, "Cannot reconstruct code from tokens")
        error_tokens = tokens.map(&:event).grep(/error/)
        assert_empty(error_tokens, 'Error tokens must be ignored if there is corresponding non-error token')
      end
    end

    def test_unterminated_heredoc_string_literal
      ['<<A;<<B', "<<A;<<B\n", "%W[\#{<<A;<<B", "%W[\#{<<A;<<B\n"].each do |code|
        tokens = RubyLex.ripper_lex_without_warning(code)
        string_literal = IRB::NestingParser.open_tokens(tokens).last
        assert_equal('<<A', string_literal&.tok)
      end
    end

    def test_indent_level_with_heredoc_and_embdoc
      reference_code = <<~EOC.chomp
        if true
          hello
          p(
          )
      EOC
      code_with_heredoc = <<~EOC.chomp
        if true
          <<~A
          A
          p(
          )
      EOC
      code_with_embdoc = <<~EOC.chomp
        if true
        =begin
        =end
          p(
          )
      EOC
      expected = 1
      assert_indent_level(reference_code.lines, expected)
      assert_indent_level(code_with_heredoc.lines, expected)
      assert_indent_level(code_with_embdoc.lines, expected)
    end

    def test_assignment_expression
      context = build_context
      ruby_lex = RubyLex.new(context)

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
          ruby_lex.assignment_expression?(exp),
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
          ruby_lex.assignment_expression?(exp),
          "#{exp.inspect}: should not be an assignment expression"
        )
      end
    end

    def test_assignment_expression_with_local_variable
      context = build_context
      ruby_lex = RubyLex.new(context)
      code = "a /1;x=1#/"
      refute(ruby_lex.assignment_expression?(code), "#{code}: should not be an assignment expression")
      context.workspace.binding.eval('a = 1')
      assert(ruby_lex.assignment_expression?(code), "#{code}: should be an assignment expression")
      refute(ruby_lex.assignment_expression?(""), "empty code should not be an assignment expression")
    end

    private

    def build_context(local_variables = nil)
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(TOPLEVEL_BINDING.dup)

      if local_variables
        local_variables.each do |n|
          workspace.binding.local_variable_set(n, nil)
        end
      end

      IRB.conf[:VERBOSE] = false
      IRB::Context.new(nil, workspace)
    end
  end
end
