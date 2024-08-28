# -*- coding: cp932 -*-
# frozen_string_literal: false
# This test is in a different file than TestUnicodeEscapes
# So that we can have a different coding comment above

require 'test/unit'

class TestMixedUnicodeEscape < Test::Unit::TestCase
  def test_basic
    # Unicode escapes do work in an sjis encoded file, but only
    # if they don't contain other multi-byte chars
    assert_equal("A", "\u0041")
    # 8-bit character escapes are okay.
    assert_equal("B\xFF", "\u0042\xFF")

    # sjis mb chars mixed with Unicode should not work
    assert_raise(SyntaxError) { eval %q("髱\u1234")}
    assert_raise(SyntaxError) { eval %q("\u{1234}髱")}

    # also should not work for Regexp
    assert_raise(RegexpError) { eval %q(/\u{1234}#{nil}髱/)}
    assert_raise(RegexpError) { eval %q(/髱#{nil}\u1234/)}

    # String interpolation turns into an expression and we get
    # a different kind of error, but we still can't mix these
    assert_raise(Encoding::CompatibilityError) { eval %q(/#{"\u1234"}#{"髱"}/)}
    assert_raise(Encoding::CompatibilityError) { eval %q("\u{1234}#{nil}髱")}
    assert_raise(Encoding::CompatibilityError) { eval %q("髱#{nil}\u1234")}
  end
end
