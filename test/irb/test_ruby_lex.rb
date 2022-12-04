$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'irb'
require 'rubygems'
require 'ostruct'

require_relative "helper"

module TestIRB
  class TestRubyLex < TestCase
    Row = Struct.new(:content, :current_line_spaces, :new_line_spaces, :nesting_level)

    class MockIO_AutoIndent
      def initialize(params, &assertion)
        @params = params
        @assertion = assertion
      end

      def auto_indent(&block)
        result = block.call(*@params)
        @assertion.call(result)
      end
    end

    def setup
      save_encodings
    end

    def teardown
      restore_encodings
    end

    def assert_indenting(lines, correct_space_count, add_new_line)
      lines = lines + [""] if add_new_line
      last_line_index = lines.length - 1
      byte_pointer = lines.last.length

      context = build_context
      context.auto_indent_mode = true
      ruby_lex = RubyLex.new()
      io = MockIO_AutoIndent.new([lines, last_line_index, byte_pointer, add_new_line]) do |auto_indent|
        error_message = "Calculated the wrong number of spaces for:\n #{lines.join("\n")}"
        assert_equal(correct_space_count, auto_indent, error_message)
      end
      ruby_lex.set_input(io, context: context)
      ruby_lex.set_auto_indent(context)
    end

    def assert_nesting_level(lines, expected, local_variables: [])
      ruby_lex = ruby_lex_for_lines(lines, local_variables: local_variables)
      error_message = "Calculated the wrong number of nesting level for:\n #{lines.join("\n")}"
      assert_equal(expected, ruby_lex.instance_variable_get(:@indent), error_message)
    end

    def assert_code_block_open(lines, expected, local_variables: [])
      ruby_lex = ruby_lex_for_lines(lines, local_variables: local_variables)
      error_message = "Wrong result of code_block_open for:\n #{lines.join("\n")}"
      assert_equal(expected, ruby_lex.instance_variable_get(:@code_block_open), error_message)
    end

    def ruby_lex_for_lines(lines, local_variables: [])
      ruby_lex = RubyLex.new()

      context = build_context(local_variables)
      io = proc{ lines.join("\n") }
      ruby_lex.set_input(io, io, context: context)
      ruby_lex.lex(context)
      ruby_lex
    end

    def test_auto_indent
      input_with_correct_indents = [
        Row.new(%q(def each_top_level_statement), nil, 2),
        Row.new(%q(  initialize_input), nil, 2),
        Row.new(%q(  catch(:TERM_INPUT) do), nil, 4),
        Row.new(%q(    loop do), nil, 6),
        Row.new(%q(      begin), nil, 8),
        Row.new(%q(        prompt), nil, 8),
        Row.new(%q(        unless l = lex), nil, 10),
        Row.new(%q(          throw :TERM_INPUT if @line == ''), nil, 10),
        Row.new(%q(        else), 8, 10),
        Row.new(%q(          @line_no += l.count("\n")), nil, 10),
        Row.new(%q(          next if l == "\n"), nil, 10),
        Row.new(%q(          @line.concat l), nil, 10),
        Row.new(%q(          if @code_block_open or @ltype or @continue or @indent > 0), nil, 12),
        Row.new(%q(            next), nil, 12),
        Row.new(%q(          end), 10, 10),
        Row.new(%q(        end), 8, 8),
        Row.new(%q(        if @line != "\n"), nil, 10),
        Row.new(%q(          @line.force_encoding(@io.encoding)), nil, 10),
        Row.new(%q(          yield @line, @exp_line_no), nil, 10),
        Row.new(%q(        end), 8, 8),
        Row.new(%q(        break if @io.eof?), nil, 8),
        Row.new(%q(        @line = ''), nil, 8),
        Row.new(%q(        @exp_line_no = @line_no), nil, 8),
        Row.new(%q(        ), nil, 8),
        Row.new(%q(        @indent = 0), nil, 8),
        Row.new(%q(      rescue TerminateLineInput), 6, 8),
        Row.new(%q(        initialize_input), nil, 8),
        Row.new(%q(        prompt), nil, 8),
        Row.new(%q(      end), 6, 6),
        Row.new(%q(    end), 4, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(end), 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_braces_on_their_own_line
      input_with_correct_indents = [
        Row.new(%q(if true), nil, 2),
        Row.new(%q(  [), nil, 4),
        Row.new(%q(  ]), 2, 2),
        Row.new(%q(end), 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_multiple_braces_in_a_line
      input_with_correct_indents = [
        Row.new(%q([[[), nil, 6),
        Row.new(%q(    ]), 4, 4),
        Row.new(%q(  ]), 2, 2),
        Row.new(%q(]), 0, 0),
        Row.new(%q([<<FOO]), 0, 0),
        Row.new(%q(hello), 0, 0),
        Row.new(%q(FOO), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_a_closed_brace_and_not_closed_brace_in_a_line
      input_with_correct_indents = [
        Row.new(%q(p() {), nil, 2),
        Row.new(%q(}), 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_symbols
      input_with_correct_indents = [
        Row.new(%q(:a), nil, 0),
        Row.new(%q(:A), nil, 0),
        Row.new(%q(:+), nil, 0),
        Row.new(%q(:@@a), nil, 0),
        Row.new(%q(:@a), nil, 0),
        Row.new(%q(:$a), nil, 0),
        Row.new(%q(:def), nil, 0),
        Row.new(%q(:`), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_endless_range_at_end_of_line
      input_with_prompt = [
        PromptRow.new('001:0: :> ', %q(a = 3..)),
        PromptRow.new('002:0: :* ', %q()),
      ]

      lines = input_with_prompt.map(&:content)
      expected_prompt_list = input_with_prompt.map(&:prompt)
      assert_dynamic_prompt(lines, expected_prompt_list)
    end

    def test_heredoc_with_embexpr
      input_with_prompt = [
        PromptRow.new('001:0:":* ', %q(<<A+%W[#{<<B)),
        PromptRow.new('002:0:":* ', %q(#{<<C+%W[)),
        PromptRow.new('003:0:":* ', %q()),
        PromptRow.new('004:0:":* ', %q(C)),
        PromptRow.new('005:0:]:* ', %q()),
        PromptRow.new('006:0:":* ', %q(]})),
        PromptRow.new('007:0:":* ', %q(})),
        PromptRow.new('008:0:":* ', %q(A)),
        PromptRow.new('009:0:]:* ', %q(B)),
        PromptRow.new('010:0:]:* ', %q(})),
        PromptRow.new('011:0: :> ', %q(])),
        PromptRow.new('012:0: :* ', %q()),
      ]

      lines = input_with_prompt.map(&:content)
      expected_prompt_list = input_with_prompt.map(&:prompt)
      assert_dynamic_prompt(lines, expected_prompt_list)
    end

    def test_backtick_method
      input_with_prompt = [
        PromptRow.new('001:0: :> ', %q(self.`(arg))),
        PromptRow.new('002:0: :* ', %q()),
        PromptRow.new('003:0: :> ', %q(def `(); end)),
        PromptRow.new('004:0: :* ', %q()),
      ]

      lines = input_with_prompt.map(&:content)
      expected_prompt_list = input_with_prompt.map(&:prompt)
      assert_dynamic_prompt(lines, expected_prompt_list)
    end

    def test_incomplete_coding_magic_comment
      input_with_correct_indents = [
        Row.new(%q(#coding:u), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_incomplete_encoding_magic_comment
      input_with_correct_indents = [
        Row.new(%q(#encoding:u), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_incomplete_emacs_coding_magic_comment
      input_with_correct_indents = [
        Row.new(%q(# -*- coding: u), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_incomplete_vim_coding_magic_comment
      input_with_correct_indents = [
        Row.new(%q(# vim:set fileencoding=u), nil, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_mixed_rescue
      input_with_correct_indents = [
        Row.new(%q(def m), nil, 2),
        Row.new(%q(  begin), nil, 4),
        Row.new(%q(    begin), nil, 6),
        Row.new(%q(      x = a rescue 4), nil, 6),
        Row.new(%q(      y = [(a rescue 5)]), nil, 6),
        Row.new(%q(      [x, y]), nil, 6),
        Row.new(%q(    rescue => e), 4, 6),
        Row.new(%q(      raise e rescue 8), nil, 6),
        Row.new(%q(    end), 4, 4),
        Row.new(%q(  rescue), 2, 4),
        Row.new(%q(    raise rescue 11), nil, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(rescue => e), 0, 2),
        Row.new(%q(  raise e rescue 14), nil, 2),
        Row.new(%q(end), 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_oneliner_method_definition
      input_with_correct_indents = [
        Row.new(%q(class A), nil, 2),
        Row.new(%q(  def foo0), nil, 4),
        Row.new(%q(    3), nil, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(  def foo1()), nil, 4),
        Row.new(%q(    3), nil, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(  def foo2(a, b)), nil, 4),
        Row.new(%q(    a + b), nil, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(  def foo3 a, b), nil, 4),
        Row.new(%q(    a + b), nil, 4),
        Row.new(%q(  end), 2, 2),
        Row.new(%q(  def bar0() = 3), nil, 2),
        Row.new(%q(  def bar1(a) = a), nil, 2),
        Row.new(%q(  def bar2(a, b) = a + b), nil, 2),
        Row.new(%q(  def bar3() = :s), nil, 2),
        Row.new(%q(  def bar4() = Time.now), nil, 2),
        Row.new(%q(end), 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
      end
    end

    def test_tlambda
      input_with_correct_indents = [
        Row.new(%q(if true), nil, 2, 1),
        Row.new(%q(  -> {), nil, 4, 2),
        Row.new(%q(  }), 2, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_corresponding_syntax_to_keyword_do_in_class
      input_with_correct_indents = [
        Row.new(%q(class C), nil, 2, 1),
        Row.new(%q(  while method_name do), nil, 4, 2),
        Row.new(%q(    3), nil, 4, 2),
        Row.new(%q(  end), 2, 2, 1),
        Row.new(%q(  foo do), nil, 4, 2),
        Row.new(%q(    3), nil, 4, 2),
        Row.new(%q(  end), 2, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_corresponding_syntax_to_keyword_do
      input_with_correct_indents = [
        Row.new(%q(while i > 0), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while true), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while ->{i > 0}.call), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while ->{true}.call), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while i > 0 do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while true do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while ->{i > 0}.call do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(while ->{true}.call do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(foo do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(foo true do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(foo ->{true} do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(foo ->{i > 0} do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_corresponding_syntax_to_keyword_for
      input_with_correct_indents = [
        Row.new(%q(for i in [1]), nil, 2, 1),
        Row.new(%q(  puts i), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_corresponding_syntax_to_keyword_for_with_do
      input_with_correct_indents = [
        Row.new(%q(for i in [1] do), nil, 2, 1),
        Row.new(%q(  puts i), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_corresponding_syntax_to_keyword_in
      input_with_correct_indents = [
        Row.new(%q(module E), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
        Row.new(%q(class A), nil, 2, 1),
        Row.new(%q(  in), nil, 4, 1)
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_bracket_corresponding_to_times
      input_with_correct_indents = [
        Row.new(%q(3.times { |i|), nil, 2, 1),
        Row.new(%q(  puts i), nil, 2, 1),
        Row.new(%q(}), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_do_corresponding_to_times
      input_with_correct_indents = [
        Row.new(%q(3.times do |i|), nil, 2, 1),
        #Row.new(%q(  puts i), nil, 2, 1),
        #Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_bracket_corresponding_to_loop
      input_with_correct_indents = [
        Row.new(%q(loop {), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(}), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_do_corresponding_to_loop
      input_with_correct_indents = [
        Row.new(%q(loop do), nil, 2, 1),
        Row.new(%q(  3), nil, 2, 1),
        Row.new(%q(end), 0, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_local_variables_dependent_code
      pend if RUBY_ENGINE == 'truffleruby'
      lines = ["a /1#/ do", "2"]
      assert_nesting_level(lines, 1)
      assert_code_block_open(lines, true)
      assert_nesting_level(lines, 0, local_variables: ['a'])
      assert_code_block_open(lines, false, local_variables: ['a'])
    end

    def test_heredoc_with_indent
      input_with_correct_indents = [
        Row.new(%q(<<~Q), 0, 0, 0),
        Row.new(%q({), 0, 0, 0),
        Row.new(%q(  #), 2, 0, 0),
        Row.new(%q(}), 0, 0, 0)
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_oneliner_def_in_multiple_lines
      input_with_correct_indents = [
        Row.new(%q(def a()=[), nil, 4, 2),
        Row.new(%q(  1,), nil, 4, 1),
        Row.new(%q(].), 0, 0, 0),
        Row.new(%q(to_s), nil, 0, 0),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    def test_broken_heredoc
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
        pend 'This test needs Ripper::Lexer#scan to take broken tokens'
      end
      input_with_correct_indents = [
        Row.new(%q(def foo), nil, 2, 1),
        Row.new(%q(  <<~Q), 2, 2, 1),
        Row.new(%q(  Qend), 2, 2, 1),
      ]

      lines = []
      input_with_correct_indents.each do |row|
        lines << row.content
        assert_indenting(lines, row.current_line_spaces, false)
        assert_indenting(lines, row.new_line_spaces, true)
        assert_nesting_level(lines, row.nesting_level)
      end
    end

    PromptRow = Struct.new(:prompt, :content)

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

    def assert_dynamic_prompt(lines, expected_prompt_list)
      pend if RUBY_ENGINE == 'truffleruby'
      ruby_lex = RubyLex.new()
      io = MockIO_DynamicPrompt.new(lines) do |prompt_list|
        error_message = <<~EOM
          Expected dynamic prompt:
          #{expected_prompt_list.join("\n")}

          Actual dynamic prompt:
          #{prompt_list.join("\n")}
        EOM
        assert_equal(expected_prompt_list, prompt_list, error_message)
      end
      ruby_lex.set_prompt do |ltype, indent, continue, line_no|
        '%03d:%01d:%1s:%s ' % [line_no, indent, ltype, continue ? '*' : '>']
      end
      context = build_context
      ruby_lex.set_input(io, context: context)
    end

    def test_dyanmic_prompt
      input_with_prompt = [
        PromptRow.new('001:1: :* ', %q(def hoge)),
        PromptRow.new('002:1: :* ', %q(  3)),
        PromptRow.new('003:0: :> ', %q(end)),
      ]

      lines = input_with_prompt.map(&:content)
      expected_prompt_list = input_with_prompt.map(&:prompt)
      assert_dynamic_prompt(lines, expected_prompt_list)
    end

    def test_dyanmic_prompt_with_blank_line
      input_with_prompt = [
        PromptRow.new('001:0:]:* ', %q(%w[)),
        PromptRow.new('002:0:]:* ', %q()),
        PromptRow.new('003:0: :> ', %q(])),
      ]

      lines = input_with_prompt.map(&:content)
      expected_prompt_list = input_with_prompt.map(&:prompt)
      assert_dynamic_prompt(lines, expected_prompt_list)
    end

    def test_broken_percent_literal
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
        pend 'This test needs Ripper::Lexer#scan to take broken tokens'
      end

      tokens = RubyLex.ripper_lex_without_warning('%wwww')
      pos_to_index = {}
      tokens.each_with_index { |t, i|
        assert_nil(pos_to_index[t.pos], "There is already another token in the position of #{t.inspect}.")
        pos_to_index[t.pos] = i
      }
    end

    def test_broken_percent_literal_in_method
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
        pend 'This test needs Ripper::Lexer#scan to take broken tokens'
      end

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
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
        pend 'This test needs Ripper::Lexer#scan to take broken tokens'
      end

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
        string_literal = RubyLex.new.check_string_literal(tokens)
        assert_equal('<<A', string_literal&.tok)
      end
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
