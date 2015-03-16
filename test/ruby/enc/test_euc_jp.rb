# vim: set fileencoding=euc-jp

require "test/unit"

class TestEUC_JP < Test::Unit::TestCase
  def test_mbc_case_fold
    assert_match(/(��)(a)\1\2/i, "��a��A")
    assert_match(/(��)(a)\1\2/i, "��a��A")
  end

  def test_property
    assert_match(/��{0}\p{Hiragana}{4}/, "�Ҥ餬��")
    assert_no_match(/��{0}\p{Hiragana}{4}/, "��������")
    assert_no_match(/��{0}\p{Hiragana}{4}/, "��������")
    assert_no_match(/��{0}\p{Katakana}{4}/, "�Ҥ餬��")
    assert_match(/��{0}\p{Katakana}{4}/, "��������")
    assert_no_match(/��{0}\p{Katakana}{4}/, "��������")
    assert_raise(RegexpError) { Regexp.new('��{0}\p{foobarbaz}') }
  end

  def test_charboundary
    assert_nil(/\xA2\xA2/ =~ "\xA1\xA2\xA2\xA3")
  end
end
