# encoding:windows-1252

require "test/unit"

class TestWindows1252 < Test::Unit::TestCase
  def test_stset
    assert_match(/^(\xdf)\1$/i, "\xdf\xdf")
    assert_match(/^(\xdf)\1$/i, "ssss")
    # assert_match(/^(\xdf)\1$/i, "\xdfss") # this must be bug...
    assert_match(/^[\xdfz]+$/i, "sszzsszz")
    assert_match(/^SS$/i, "\xdf")
    assert_match(/^Ss$/i, "\xdf")
  end

  def test_windows_1252
    [0x8a, 0x8c, 0x8e, *0xc0..0xd6, *0xd8..0xde, 0x9f].zip([0x9a, 0x9c, 0x9e, *0xe0..0xf6, *0xf8..0xfe, 0xff]).each do |c1, c2|
      c1 = c1.chr("windows-1252")
      c2 = c2.chr("windows-1252")
      assert_match(/^(#{ c1 })\1$/i, c2 + c1)
      assert_match(/^(#{ c2 })\1$/i, c1 + c2)
      assert_match(/^[#{ c1 }]+$/i, c2 + c1)
      assert_match(/^[#{ c2 }]+$/i, c1 + c2)
    end
  end
end
