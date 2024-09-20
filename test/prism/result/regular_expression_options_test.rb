# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class RegularExpressionOptionsTest < TestCase
    def test_options
      assert_equal "", Prism.parse_statement("__FILE__").filepath
      assert_equal "foo.rb", Prism.parse_statement("__FILE__", filepath: "foo.rb").filepath

      assert_equal 1, Prism.parse_statement("foo").location.start_line
      assert_equal 10, Prism.parse_statement("foo", line: 10).location.start_line

      refute Prism.parse_statement("\"foo\"").frozen?
      assert Prism.parse_statement("\"foo\"", frozen_string_literal: true).frozen?
      refute Prism.parse_statement("\"foo\"", frozen_string_literal: false).frozen?

      assert_kind_of CallNode, Prism.parse_statement("foo")
      assert_kind_of LocalVariableReadNode, Prism.parse_statement("foo", scopes: [[:foo]])
      assert_equal 1, Prism.parse_statement("foo", scopes: [[:foo], []]).depth

      assert_equal [:foo], Prism.parse("foo", scopes: [[:foo]]).value.locals
    end
  end
end
