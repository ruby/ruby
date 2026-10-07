# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class RegularExpressionOptionsTest < TestCase
    def test_options
      assert_equal "", Ruby::Prism.parse_statement("__FILE__").filepath
      assert_equal "foo.rb", Ruby::Prism.parse_statement("__FILE__", filepath: "foo.rb").filepath

      assert_equal 1, Ruby::Prism.parse_statement("foo").location.start_line
      assert_equal 10, Ruby::Prism.parse_statement("foo", line: 10).location.start_line

      refute Ruby::Prism.parse_statement("\"foo\"").frozen?
      assert Ruby::Prism.parse_statement("\"foo\"", frozen_string_literal: true).frozen?
      refute Ruby::Prism.parse_statement("\"foo\"", frozen_string_literal: false).frozen?

      assert_kind_of CallNode, Ruby::Prism.parse_statement("foo")
      assert_kind_of LocalVariableReadNode, Ruby::Prism.parse_statement("foo", scopes: [[:foo]])
      assert_equal 1, Ruby::Prism.parse_statement("foo", scopes: [[:foo], []]).depth

      assert_equal [:foo], Ruby::Prism.parse("foo", scopes: [[:foo]]).value.locals
    end
  end
end
