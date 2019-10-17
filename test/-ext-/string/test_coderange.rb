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
end
