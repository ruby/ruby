# frozen_string_literal: false
require 'test/unit'
require 'irb/ruby-lex'
require 'stringio'

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    def setup
      @scanner = RubyLex.new
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
