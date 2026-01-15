# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "test_helper"

begin
  require "onigmo"
rescue LoadError
  # In CRuby's CI, we're not going to test against the parser gem because we
  # don't want to have to install it. So in this case we'll just skip this test.
  return
end

module Prism
  class OnigmoTest < TestCase
    def test_ONIGERR_PARSE_DEPTH_LIMIT_OVER
      assert_error(%Q{#{"(" * 4096}a#{")" * 4096}}, "parse depth limit over")
    end

    def test_ONIGERR_EMPTY_CHAR_CLASS
      assert_error("[]", "empty char-class")
    end

    def test_ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED
      assert_error("*", "target of repeat operator is not specified")
      assert_error("+", "target of repeat operator is not specified")
      assert_error("?", "target of repeat operator is not specified")
    end

    def test_ONIGERR_EMPTY_GROUP_NAME
      assert_error("(?<>)", "group name is empty")
    end

    def test_ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS
      assert_error("(", "end pattern with unmatched parenthesis")
      assert_error("(|", "end pattern with unmatched parenthesis")
      assert_error("(?<", "end pattern with unmatched parenthesis")
    end

    def test_ONIGERR_END_PATTERN_IN_GROUP
      assert_error("(?", "end pattern in group")
      assert_error("(?#", "end pattern in group")
    end

    def test_ONIGERR_UNDEFINED_GROUP_OPTION
      assert_error("(?P", "undefined group option")
    end

    def test_ONIGERR_UNMATCHED_CLOSE_PARENTHESIS
      assert_error(")", "unmatched close parenthesis")
    end

    private

    def assert_error(source, message)
      result = Prism.parse("/#{source}/")

      assert result.failure?, "Expected #{source.inspect} to error"
      assert_equal message, result.errors.first.message

      error = assert_raise(ArgumentError) { Onigmo.parse(source) }
      assert_equal message, error.message
    end
  end
end
