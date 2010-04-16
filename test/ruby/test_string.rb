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

  def test_ord
    original_kcode = $KCODE

    assert_raise(ArgumentError) { "".ord }

    str_abc = "ABC"
    str_a_i_U = "\xE3\x81\x82\xE3\x81\x84"
    str_a_i_E = "\xA4\xA2\xA4\xA4"
    str_a_i_S = "\x82\xA0\x82\xA2"
    str_ai_U = "\xEF\xBD\xB1\xEF\xBD\xB2"
    str_ai_E = "\x8E\xB1\x8E\xB2"
    str_ai_S = "\xB1\xB2"

    $KCODE = 'n'
    assert_equal(0x41, str_abc.ord)
    assert_equal(0xE3, str_a_i_U.ord)
    assert_equal(0xA4, str_a_i_E.ord)
    assert_equal(0x82, str_a_i_S.ord)
    assert_equal(0xEF, str_ai_U.ord)
    assert_equal(0x8E, str_ai_E.ord)
    assert_equal(0xB1, str_ai_S.ord)

    $KCODE = 'u'
    assert_equal(0x41, str_abc.ord)
    assert_equal(0x3042, str_a_i_U.ord)
    assert_raise(ArgumentError) { str_a_i_U[0..0].ord }
    assert_raise(ArgumentError) { str_a_i_U[0..1].ord }
    assert_equal(0xFF71, str_ai_U.ord)

    $KCODE = 's'
    assert_equal(0x41, str_abc.ord)
    assert_equal(0x82A0, str_a_i_S.ord)
    assert_raise(ArgumentError) { str_a_i_S[0..0].ord }
    assert_equal(0xB1, str_ai_S.ord)

    $KCODE = 'e'
    assert_equal(0x41, str_abc.ord)
    assert_equal(0xA4A2, str_a_i_E.ord)
    assert_raise(ArgumentError) { str_a_i_E[0..0].ord }
    assert_equal(0x8EB1, str_ai_E.ord)
  ensure
    $KCODE = original_kcode
  end

  def test_inspect
    original_kcode = $KCODE

    $KCODE = 'n'
    assert_equal('"\343\201\202"', "\xe3\x81\x82".inspect)

    $KCODE = 'u'
    assert_equal("\"\xe3\x81\x82\"", "\xe3\x81\x82".inspect)
    assert_no_match(/\0/, "\xe3\x81".inspect, '[ruby-dev:39550]')
  ensure
    $KCODE = original_kcode
  end

  def test_split
    result = " now's  the time".split
    assert_equal("now's", result[0])
    assert_equal("the", result[1])
    assert_equal("time", result[2])

    result = " now's  the time".split(' ')
    assert_equal("now's", result[0])
    assert_equal("the", result[1])
    assert_equal("time", result[2])

    result = " now's  the time".split(/ /)
    assert_equal("", result[0])
    assert_equal("now's", result[1])
    assert_equal("", result[2])
    assert_equal("the", result[3])
    assert_equal("time", result[4])

    result = "1, 2.34,56, 7".split(%r{,\s*})
    assert_equal("1", result[0])
    assert_equal("2.34", result[1])
    assert_equal("56", result[2])
    assert_equal("7", result[3])

    result = "1, 2.34,56".split(%r{(,\s*)})
    assert_equal("1", result[0])
    assert_equal(", ", result[1])
    assert_equal("2.34", result[2])
    assert_equal(",", result[3])
    assert_equal("56", result[4])

    result = "wd :sp: wd".split(/(:(\w+):)/)
    assert_equal("wd ", result[0])
    assert_equal(":sp:", result[1])
    assert_equal("sp", result[2])
    assert_equal(" wd", result[3])

    result = "hello".split(//)
    assert_equal("h", result[0])
    assert_equal("e", result[1])
    assert_equal("l", result[2])
    assert_equal("l", result[3])
    assert_equal("o", result[4])

    result = "hello".split(//, 3)
    assert_equal("h", result[0])
    assert_equal("e", result[1])
    assert_equal("llo", result[2])

    result = "hi mom".split(%r{\s*})
    assert_equal("h", result[0])
    assert_equal("i", result[1])
    assert_equal("m", result[2])
    assert_equal("o", result[3])
    assert_equal("m", result[4])

    result = "mellow yellow".split("ello")
    assert_equal("m", result[0])
    assert_equal("w y", result[1])
    assert_equal("w", result[2])

    result = "1,2,,3,4,,".split(',')
    assert_equal("1", result[0])
    assert_equal("2", result[1])
    assert_equal("", result[2])
    assert_equal("3", result[3])
    assert_equal("4", result[4])

    result = "1,2,,3,4,,".split(',', 4)
    assert_equal("1", result[0])
    assert_equal("2", result[1])
    assert_equal("", result[2])
    assert_equal("3,4,,", result[3])

    result = "1,2,,3,4,,".split(',', -4)
    assert_equal("1", result[0])
    assert_equal("2", result[1])
    assert_equal("", result[2])
    assert_equal("3", result[3])
    assert_equal("4", result[4])
    assert_equal("", result[5])
    assert_equal("", result[6])
  end
end
