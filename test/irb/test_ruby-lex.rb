# frozen_string_literal: false
require 'test/unit'
require 'irb/ruby-lex'

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    def setup
      @scanner = RubyLex.new
    end

    def test_set_input_proc
      called = false
      @scanner.set_input(self) {|x| called = true; nil}
      assert_nil(@scanner.lex)
      assert(called)
    end
  end
end
