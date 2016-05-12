# frozen_string_literal: false
require "rexml/text"

module REXMLTests
  class TextTester < Test::Unit::TestCase
    include REXML

    def test_shift_operator_chain
      text = Text.new("original\r\n")
      text << "append1\r\n" << "append2\r\n"
      assert_equal("original\nappend1\nappend2\n", text.to_s)
    end

    def test_shift_operator_cache
      text = Text.new("original\r\n")
      text << "append1\r\n" << "append2\r\n"
      assert_equal("original\nappend1\nappend2\n", text.to_s)
      text << "append3\r\n" << "append4\r\n"
      assert_equal("original\nappend1\nappend2\nappend3\nappend4\n", text.to_s)
    end
  end
end
