# frozen_string_literal: false
require 'test/unit'
require 'irb/ruby-lex'
require 'stringio'

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    def setup
      @scanner = RubyLex.new
    end

    def teardown
      RubyLex.debug_level = 0
    end

    def test_set_input_proc
      called = false
      @scanner.set_input(nil) {called = true; nil}
      @scanner.each_top_level_statement {}
      assert(called)
    end

    def test_comment
      assert_equal([["#\n", 1]], top_level_statement("#\n"))
    end

    def test_top_level_statement
      result = top_level_statement("#{<<-"begin;"}#{<<~"end;"}")
      begin;
        begin
        end
        begin
        end
      end;
      assert_equal([
                     ["begin\n""end\n", 1],
                     ["begin\n""end\n", 3],
                   ],
                   result)
    end

    def test_immature_statement
      src = "if false\n"
      assert_equal([[src, 1]], top_level_statement(src))
    end

    def test_prompt
      prompts = []
      @scanner.set_prompt {|*a|
        a << @scanner.instance_variable_get(:@lex_state)
        unless prompts.last == a
          prompts << a
        end
      }
      src = "#{<<-"begin;"}#{<<~"end;"}"
      begin;
        if false or
          true
          "
          "
          '
          '
        else
          nil
          nil
        end
      end;
      assert_equal([[src, 1]], top_level_statement(src))
      expected = [
        [nil, 0, false],
        [nil, 1, true],
        [nil, 1, false],
        ['"', 1, false],
        [nil, 1, false],
        ["'", 1, false],
        [nil, 1, false],
        [nil, 1, true], # FIXME: just after `else' should be `false'
        [nil, 1, false],
        [nil, 1, false],
        [nil, 0, false],
      ]
      srcs = src.lines
      assert_equal(expected.size, prompts.size)
      expected.each_with_index {|e, i|
        assert_equal(i + 1, prompts[i][3])
        assert_equal(e, prompts[i][0..2], "#{i+1}: #{srcs[i]} # #{prompts[i]}")
      }
    end

    def top_level_statement(lines)
      input = InputLines.new(lines, "r")
      scanned = []
      @scanner.set_input(input)
      @scanner.each_top_level_statement {|*e|
        scanned << e
        yield(*e) if defined?(yield)
      }
      scanned
    end

    class InputLines < StringIO
      alias encoding external_encoding
    end
  end
end
