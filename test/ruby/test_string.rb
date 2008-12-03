require 'test/unit'

class TestString < Test::Unit::TestCase
  def check_sum(str, bits=16)
    sum = 0
    str.each_byte {|c| sum += c}
    sum = sum & ((1 << bits) - 1) if bits != 0
    assert_equal(sum, str.sum(bits))
  end

  def test_sum
    assert_equal(0, "".sum)
    assert_equal(294, "abc".sum)
    check_sum("abc")
    check_sum("\x80")
    0.upto(70) {|bits|
      check_sum("xyz", bits)
    }
  end

  def test_succ
    assert_equal("abd", "abc".succ)
    assert_equal("z",   "y".succ)
    assert_equal("aaa", "zz".succ)

    assert_equal("124",  "123".succ)
    assert_equal("1000", "999".succ)
    assert_equal("2.000", "1.999".succ)

    assert_equal("2000aaa",  "1999zzz".succ)
    assert_equal("AAAAA000", "ZZZZ999".succ)
    assert_equal("*+", "**".succ)

    assert_equal("abce", "abcd".succ)
    assert_equal("THX1139", "THX1138".succ)
    assert_equal("<<koalb>>", "<<koala>>".succ)
    assert_equal("2000aaa", "1999zzz".succ)
    assert_equal("AAAA0000", "ZZZ9999".succ)
    assert_equal("**+", "***".succ)
  end

  def test_succ!
    a = "abc"
    b = a.dup
    assert_equal("abd", a.succ!)
    assert_equal("abd", a)
    assert_equal("abc", b)

    a = "y"
    assert_equal("z", a.succ!)
    assert_equal("z", a)

    a = "zz"
    assert_equal("aaa", a.succ!)
    assert_equal("aaa", a)

    a = "123"
    assert_equal("124", a.succ!)
    assert_equal("124", a)

    a = "999"
    assert_equal("1000", a.succ!)
    assert_equal("1000", a)

    a = "1999zzz"
    assert_equal("2000aaa", a.succ!)
    assert_equal("2000aaa", a)

    a = "ZZZZ999"
    assert_equal("AAAAA000", a.succ!)
    assert_equal("AAAAA000", a)

    a = "**"
    assert_equal("*+", a.succ!)
    assert_equal("*+", a)

    assert_equal("aaaaaaaaaaaa", "zzzzzzzzzzz".succ!)
    assert_equal("aaaaaaaaaaaaaaaaaaaaaaaa", "zzzzzzzzzzzzzzzzzzzzzzz".succ!)
  end

  def test_getbyte
    assert_equal(0x82, "\xE3\x81\x82\xE3\x81\x84".getbyte(2))
    assert_equal(0x82, "\xE3\x81\x82\xE3\x81\x84".getbyte(-4))
    assert_nil("\xE3\x81\x82\xE3\x81\x84".getbyte(100))
  end

  def test_setbyte
    s = "\xE3\x81\x82\xE3\x81\x84"
    s.setbyte(2, 0x84)
    assert_equal("\xE3\x81\x84\xE3\x81\x84", s)

    s = "\xE3\x81\x82\xE3\x81\x84"
    assert_raise(IndexError) { s.setbyte(100, 0) }

    s = "\xE3\x81\x82\xE3\x81\x84"
    s.setbyte(-4, 0x84)
    assert_equal("\xE3\x81\x84\xE3\x81\x84", s)
  end
end
