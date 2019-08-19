# frozen_string_literal: false

require_relative "rexml_test_utils"

module REXMLTests
  class TextTester < Test::Unit::TestCase
    include REXML

    def test_new_text_response_whitespace_default
      text = Text.new("a  b\t\tc", true)
      assert_equal("a b\tc", Text.new(text).to_s)
    end

    def test_new_text_response_whitespace_true
      text = Text.new("a  b\t\tc", true)
      assert_equal("a  b\t\tc", Text.new(text, true).to_s)
    end

    def test_new_text_raw_default
      text = Text.new("&amp;lt;", false, nil, true)
      assert_equal("&amp;lt;", Text.new(text).to_s)
    end

    def test_new_text_raw_false
      text = Text.new("&amp;lt;", false, nil, true)
      assert_equal("&amp;amp;lt;", Text.new(text, false, nil, false).to_s)
    end

    def test_new_text_entity_filter_default
      document = REXML::Document.new(<<-XML)
<!DOCTYPE root [
  <!ENTITY a "aaa">
  <!ENTITY b "bbb">
]>
<root/>
      XML
      text = Text.new("aaa bbb", false, document.root, nil, ["a"])
      assert_equal("aaa &b;",
                   Text.new(text, false, document.root).to_s)
    end

    def test_new_text_entity_filter_custom
      document = REXML::Document.new(<<-XML)
<!DOCTYPE root [
  <!ENTITY a "aaa">
  <!ENTITY b "bbb">
]>
<root/>
      XML
      text = Text.new("aaa bbb", false, document.root, nil, ["a"])
      assert_equal("&a; bbb",
                   Text.new(text, false, document.root, nil, ["b"]).to_s)
    end

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

    def test_clone
      text = Text.new("&amp;lt; <")
      assert_equal(text.to_s,
                   text.clone.to_s)
    end
  end
end
