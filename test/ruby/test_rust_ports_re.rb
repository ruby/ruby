# frozen_string_literal: false
#
# Ruby-level tests for re.c's check_unicode_range (port unit re-A-02,
# core_rs/src/re.rs), reached through the \u escapes of a regexp source
# (append_utf8 for \uXXXX, unescape_unicode_list for \u{...}).  They pass with
# and without --with-rust-ports.
require 'test/unit'

class TestRustPortsRe < Test::Unit::TestCase
  def test_surrogates_are_invalid
    %w[d800 dbff dc00 dfff].each do |hex|
      assert_raise_with_message(RegexpError, /invalid Unicode range/, hex) { Regexp.new("\\u#{hex}") }
      assert_raise_with_message(RegexpError, /invalid Unicode range/, hex) { Regexp.new("\\u{#{hex}}") }
    end
  end

  def test_beyond_max_is_invalid
    %w[110000 7fffffff].each do |hex|
      assert_raise_with_message(RegexpError, /invalid Unicode range/, hex) { Regexp.new("\\u{#{hex}}") }
    end
    assert_raise_with_message(RegexpError, /invalid Unicode range/) { Regexp.new("\\u{41 110000}") }
  end

  def test_valid_boundaries
    { "d7ff" => "\u{d7ff}", "e000" => "\u{e000}", "ffff" => "\u{ffff}", "10ffff" => "\u{10ffff}", "41" => "A" }.each do |hex, ch|
      assert_match(Regexp.new("\\A\\u{#{hex}}\\z"), ch, hex)
    end
    assert_match(Regexp.new("\\A\\u{41 10ffff}\\z"), "A\u{10ffff}")
    assert_match(Regexp.new("\\A\\ud7ff\\z"), "\u{d7ff}")
  end
end
