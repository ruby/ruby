# encoding:windows-1251
# frozen_string_literal: false

require "test/unit"

class TestWindows1251 < Test::Unit::TestCase
  def test_windows_1251
    (0xc0..0xdf).each do |c|
      c1 = c.chr("windows-1251")
      c2 = (c + 0x20).chr("windows-1251")
      assert_match(/^(#{ c1 })\1$/i, c2 + c1)
      assert_match(/^(#{ c2 })\1$/i, c1 + c2)
      assert_match(/^[#{ c1 }]+$/i, c2 + c1)
      assert_match(/^[#{ c2 }]+$/i, c1 + c2)
    end
  end

  def test_ascii_control_is_not_print
    [*0x00..0x1f, 0x7f].each do |c|
      assert_not_match(/\A[[:print:]]/, c.chr("windows-1251") + "\xC0")
    end
  end
end
