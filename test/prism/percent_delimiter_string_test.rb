# frozen_string_literal: true

require_relative "test_helper"

module Prism
  module PercentDelimiterTests
    def test_newline_terminator_with_lf_crlf
      str = l "\n123456\r\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_lf_crlf_with_extra_cr
      str = l "\n123456\r\r\n"
      assert_parse "123456\r", str
    end

    def test_newline_terminator_with_crlf_pair
      str = l "\r\n123456\r\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_crlf_crlf_with_extra_cr
      str = l "\r\n123456\r\r\n"
      assert_parse "123456\r", str
    end

    def test_newline_terminator_with_cr_cr
      str = l "\r123456\r;\n"
      assert_parse "123456", str
    end

    def test_newline_terminator_with_crlf_lf
      str = l "\r\n123456\n;\n"
      assert_parse "123456", str
    end

    def test_cr_crlf
      str = l "\r1\r\n \r"
      assert_parse "1\n ", str
    end

    def test_lf_crlf
      str = l "\n1\r\n \n"
      assert_parse "1", str
    end

    def test_lf_lf
      str = l "\n1\n \n"
      assert_parse "1", str
    end

    def assert_parse(expected, str)
      assert_equal expected, find_node(str).unescaped
    end
  end

  class PercentDelimiterStringTest < TestCase
    include PercentDelimiterTests

    def find_node(str)
      tree = Prism.parse str
      tree.value.breadth_first_search { |x| Prism::StringNode === x }
    end

    def l(str)
      "%" + str
    end
  end

  class PercentDelimiterRegexpTest < TestCase
    include PercentDelimiterTests

    def l(str)
      "%r" + str
    end

    def find_node(str)
      tree = Prism.parse str
      tree.value.breadth_first_search { |x| Prism::RegularExpressionNode === x }
    end
  end
end
