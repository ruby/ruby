# vim: set fileencoding=shift_jis
# frozen_string_literal: false

require "test/unit"

class TestShiftJIS < Test::Unit::TestCase
  def test_mbc_case_fold
    assert_match(/(��)(a)\1\2/i, "��a��A")
    assert_match(/(��)(a)\1\2/i, "��a�`A")
  end

  def test_property
    assert_match(/��{0}\p{Hiragana}{4}/, "�Ђ炪��")
    assert_no_match(/��{0}\p{Hiragana}{4}/, "�J�^�J�i")
    assert_no_match(/��{0}\p{Hiragana}{4}/, "��������")
    assert_no_match(/��{0}\p{Katakana}{4}/, "�Ђ炪��")
    assert_match(/��{0}\p{Katakana}{4}/, "�J�^�J�i")
    assert_no_match(/��{0}\p{Katakana}{4}/, "��������")
    assert_raise(RegexpError) { Regexp.new('��{0}\p{foobarbaz}') }
  end

  def test_code_to_mbclen
    s = "����������"
    s << 0x82a9
    assert_equal("������������", s)
    assert_raise(RangeError) { s << 0x82 }
  end
end
