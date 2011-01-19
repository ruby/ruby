######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require "rubygems/text"

class TestGemText < RubyGemTestCase
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
  end

  def test_levenshtein_distance_replace
    assert_equal 2, levenshtein_distance("zentest", "ZenTest")
    assert_equal 7, levenshtein_distance("xxxxxxx", "ZenTest")
    assert_equal 7, levenshtein_distance("zentest", "xxxxxxx")
  end
end
