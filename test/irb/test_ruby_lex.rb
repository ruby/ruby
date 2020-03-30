$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'irb/ruby-lex'
require 'test/unit'
require 'ostruct'

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    Row = Struct.new(:content, :current_line_spaces, :new_line_spaces)

    class MockIO
      def initialize(params, &assertion)
        @params = params
        @assertion = assertion
      end

      def auto_indent(&block)
        result = block.call(*@params)
        @assertion.call(result)
      end
    end

    def assert_indenting(lines, correct_space_count, add_new_line)
      lines = lines + [""] if add_new_line
      last_line_index = lines.length - 1
      byte_pointer = lines.last.length

      ruby_lex = RubyLex.new()
      io = MockIO.new([lines, last_line_index, byte_pointer, add_new_line]) do |auto_indent|
        error_message = "Calculated the wrong number of spaces for:\n #{lines.join("\n")}"
        assert_equal(correct_space_count, auto_indent, error_message)
      end
      ruby_lex.set_input(io)
      context = OpenStruct.new(auto_indent_mode: true)
      ruby_lex.set_auto_indent(context)
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
        Row.new(%q([<<FOO]), nil, 0),
        Row.new(%q(hello), nil, 0),
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
  end
end
