# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class PercentDelimiterStringTest < TestCase
    def test_newline_terminator_with_lf_crlf
      str = "%\n123456\r\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_lf_crlf_with_extra_cr
      str = "%\n123456\r\r\n"
      assert_parse "123456\r", str
    end

    def test_newline_terminator_with_crlf_pair
      str = "%\r\n123456\r\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_crlf_crlf_with_extra_cr
      str = "%\r\n123456\r\r\n"
      assert_parse "123456\r", str
    end

    def test_newline_terminator_with_cr_cr
      str = "%\r123456\r;\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_crlf_lf
      str = "%\r\n123456\n;\n"
      assert_parse "123456", str
    end

    def test_cr_crlf
      str = "%\r1\r\n \r"
      assert_parse "1\n ", str
    end

    def test_lf_crlf
      str = "%\n1\r\n \n"
      assert_parse "1", str
    end

    def test_lf_lf
      str = "%\n1\n \n"
      assert_parse "1", str
    end

    def assert_parse(expected, str)
      tree = Prism.parse str
      node = tree.value.breadth_first_search { |x| Prism::StringNode === x }
      assert_equal expected, node.unescaped
    end
  end
end
