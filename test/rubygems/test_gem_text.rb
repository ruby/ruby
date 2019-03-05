# frozen_string_literal: true
require 'rubygems/test_case'
require "rubygems/text"

class TestGemText < Gem::TestCase

  include Gem::Text

  def test_format_text
    assert_equal "text to\nwrap",     format_text("text to wrap", 8)
  end

  def test_format_text_indent
    assert_equal "  text to\n  wrap", format_text("text to wrap", 8, 2)
  end

  def test_format_text_none
    assert_equal "text to wrap",      format_text("text to wrap", 40)
  end

  def test_format_text_none_indent
    assert_equal "  text to wrap",    format_text("text to wrap", 40, 2)
  end

  def test_format_text_no_space
    assert_equal "texttowr\nap",     format_text("texttowrap", 8)
  end

  def test_format_text_trailing # for two spaces after .
    text = <<-TEXT
This line is really, really long.  So long, in fact, that it is more than eighty characters long!  The purpose of this line is for testing wrapping behavior because sometimes people don't wrap their text to eighty characters.  Without the wrapping, the text might not look good in the RSS feed.
    TEXT

    expected = <<-EXPECTED
This line is really, really long.  So long, in fact, that it is more than
eighty characters long!  The purpose of this line is for testing wrapping
behavior because sometimes people don't wrap their text to eighty characters.
Without the wrapping, the text might not look good in the RSS feed.
    EXPECTED

    assert_equal expected, format_text(text, 78)
  end

  def test_format_removes_nonprintable_characters
    assert_equal "text with weird .. stuff .", format_text("text with weird \x1b\x02 stuff \x7f", 40)
  end

  def test_min3
    assert_equal 1, min3(1, 1, 1)
    assert_equal 1, min3(1, 1, 2)
    assert_equal 1, min3(1, 2, 1)
    assert_equal 1, min3(2, 1, 1)
    assert_equal 1, min3(1, 2, 2)
    assert_equal 1, min3(2, 1, 2)
    assert_equal 1, min3(2, 2, 1)
    assert_equal 1, min3(1, 2, 3)
    assert_equal 1, min3(1, 3, 2)
    assert_equal 1, min3(2, 1, 3)
    assert_equal 1, min3(2, 3, 1)
    assert_equal 1, min3(3, 1, 2)
    assert_equal 1, min3(3, 2, 1)
  end

  def test_levenshtein_distance_add
    assert_equal 2, levenshtein_distance("zentest", "zntst")
    assert_equal 2, levenshtein_distance("zntst", "zentest")
  end

  def test_levenshtein_distance_empty
    assert_equal 5, levenshtein_distance("abcde", "")
    assert_equal 5, levenshtein_distance("", "abcde")
  end

  def test_levenshtein_distance_remove
    assert_equal 3, levenshtein_distance("zentest", "zentestxxx")
    assert_equal 3, levenshtein_distance("zentestxxx", "zentest")
    assert_equal 13, levenshtein_distance("cat", "thundercatsarego")
    assert_equal 13, levenshtein_distance("thundercatsarego", "cat")
  end

  def test_levenshtein_distance_replace
    assert_equal 2, levenshtein_distance("zentest", "ZenTest")
    assert_equal 7, levenshtein_distance("xxxxxxx", "ZenTest")
    assert_equal 7, levenshtein_distance("zentest", "xxxxxxx")
  end

  def test_truncate_text
    assert_equal "abc", truncate_text("abc", "desc")
    assert_equal "Truncating desc to 2 characters:\nab", truncate_text("abc", "desc", 2)
    s = "ab" * 500_001
    assert_equal "Truncating desc to 1,000,000 characters:\n#{s[0, 1_000_000]}", truncate_text(s, "desc", 1_000_000)
  end

  def test_clean_text
    assert_equal ".]2;nyan.", clean_text("\e]2;nyan\a")
  end

end
