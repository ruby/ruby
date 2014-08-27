require "test/unit"

class TestEucKr < Test::Unit::TestCase
  def s(s)
    s.force_encoding("euc-kr")
  end

  def test_mbc_enc_len
    assert_equal(1, s("\xa1\xa1").size)
  end

  def test_mbc_to_code
    assert_equal(0xa1a1, s("\xa1\xa1").ord)
  end

  def test_code_to_mbc
    assert_equal(s("\xa1\xa1"), 0xa1a1.chr("euc-kr"))
  end

  def test_mbc_case_fold
    r = Regexp.new(s("(\xa1\xa1)\\1"), "i")
    assert_match(r, s("\xa1\xa1\xa1\xa1"))
  end

  def test_left_adjust_char_head
    assert_equal(s("\xa1\xa1"), s("\xa1\xa1\xa1\xa1").chop)
  end

  def test_euro_sign
    assert_equal("\u{20ac}", s("\xa2\xe6").encode("utf-8"))
  end

  def test_registered_mark
    assert_equal("\u{00ae}", s("\xa2\xe7").encode("utf-8"))
  end
end
