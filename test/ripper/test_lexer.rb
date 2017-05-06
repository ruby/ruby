# frozen_string_literal: true
begin
  require_relative 'dummyparser'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Lexer < Test::Unit::TestCase
  def test_nested_dedent_heredoc
    bug = '[ruby-core:80977] [Bug #13536]'
    str = <<~'E'
    <<~"D"
    #{
    <<~"B"
    this must be a valid ruby
    B
    }
    D
    E
    assert_equal(str, Ripper.tokenize(str).join(""), bug)

    str = <<~'E'
    <<~"D"
    #{
    <<~"B"
      this must be a valid ruby
    B
    }
    D
    E
    assert_equal(str, Ripper.tokenize(str).join(""), bug)
  end
end
