# coding: ascii-8bit
# frozen_string_literal: false
require 'test/unit'
require "-test-/string"
require "rbconfig/sizeof"

class Test_StringCoderange < Test::Unit::TestCase
  def setup
    @sizeof_voidp = RbConfig::SIZEOF["void*"]
    @a8 = Encoding::ASCII_8BIT
    @a7 = Encoding::US_ASCII
    @u8 = Encoding::UTF_8
  end

  def test_ascii8bit
    enc = @a8
    str = "a"
    str.force_encoding(enc)
    assert_equal :"7bit", Bug::String.new(str).coderange_scan

    str = "a\xBE".force_encoding(enc)
    assert_equal :valid, Bug::String.new(str).coderange_scan
  end

  def test_usascii
    enc = @a7
    str = "a"
    str.force_encoding(enc)
    assert_equal :"7bit", Bug::String.new(str).coderange_scan

    str = "a" * (@sizeof_voidp * 2)
    str << "\xBE"
    str.force_encoding(enc)
    assert_equal :broken, Bug::String.new(str).coderange_scan
  end

  def test_utf8
    enc = @u8
    str = "a"
    str.force_encoding(enc)
    assert_equal :"7bit", Bug::String.new(str).coderange_scan

    str = "a" * (@sizeof_voidp * 3)
    str << "aa\xC2\x80"
    str.force_encoding(enc)
    assert_equal :valid, Bug::String.new(str).coderange_scan

    str = "a" * (@sizeof_voidp * 2)
    str << "\xC2\x80"
    str << "a" * (@sizeof_voidp * 2)
    str.force_encoding(enc)
    assert_equal :valid, Bug::String.new(str).coderange_scan

    str = "a" * (@sizeof_voidp * 2)
    str << "\xC1\x80"
    str << "a" * (@sizeof_voidp * 2)
    str.force_encoding(enc)
    assert_equal :broken, Bug::String.new(str).coderange_scan
  end

  def test_subseq_does_not_keep_valid_across_split_char
    [1, 100].each do |n|
      str = Bug::String.new(("\xC3\xA9" * n * 2).force_encoding(@u8))
      assert_equal :valid, str.coderange_scan
      len = str.bytesize

      [[1, len - 1], [0, len - 1], [1, 2]].each do |beg, l|
        sub, cr = str.subseq_coderange(beg, l)
        assert_equal :unknown, cr, [n, beg, l].inspect
        assert_not_predicate sub, :valid_encoding?, [n, beg, l].inspect
      end

      sub, cr = str.subseq_coderange(2, len - 2)
      assert_equal :unknown, cr
      assert_predicate sub, :valid_encoding?
    end

    str = Bug::String.new("a\xC3\xA9".force_encoding(@u8))
    assert_equal :valid, str.coderange_scan
    sub, cr = str.subseq_coderange(0, 1)
    assert_equal :unknown, cr
    assert_predicate sub, :ascii_only?
    assert_equal :"7bit", str.subseq_coderange(1, 0)[1]

    str = Bug::String.new("abc".force_encoding(@u8))
    assert_equal :"7bit", str.coderange_scan
    assert_equal :"7bit", str.subseq_coderange(1, 1)[1]
  end

  def test_subseq_non_utf8
    sjis = Encoding::Shift_JIS
    str = Bug::String.new("\x95\x5C\x95\x5C".force_encoding(sjis))
    assert_equal :valid, str.coderange_scan

    sub, cr = str.subseq_coderange(1, 2)
    assert_equal sjis, sub.encoding
    assert_equal :unknown, cr
    assert_not_predicate sub, :valid_encoding?

    sub, cr = str.subseq_coderange(0, 2)
    assert_equal :unknown, cr
    assert_predicate sub, :valid_encoding?

    str = Bug::String.new("a".encode(Encoding::UTF_16LE))
    str.coderange_scan
    assert_equal :valid, str.subseq_coderange(0, 0)[1]
  end
end
