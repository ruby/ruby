# frozen_string_literal: false
require 'test/unit'
require "-test-/string"

class Test_StringEncStrBufCat < Test::Unit::TestCase
  Bug6509 = '[ruby-dev:45688]'

  def test_unknown
    a8_str = "a\xBE".force_encoding(Encoding::ASCII_8BIT)
    cr_unknown_str = [0x62].pack('C*')
    assert_equal(true, a8_str.valid_encoding?, "an assertion for following tests")
    assert_equal(:valid, Bug::String.new(a8_str).coderange, "an assertion for following tests")
    assert_equal(:unknown, Bug::String.new(cr_unknown_str).coderange, "an assertion for following tests")
    assert_equal(:valid, Bug::String.new(a8_str).enc_str_buf_cat(cr_unknown_str).coderange, Bug6509)
  end

  def test_str_conv_enc
    str = Bug::String.new("aaa".encode("US-ASCII"))
    assert_same(str, str.str_conv_enc_opts("UTF-8", "US-ASCII", 0, nil))

    str = Bug::String.new("aaa".encode("UTF-16LE").force_encoding("UTF-8"))
    assert_predicate(str, :ascii_only?) # cache coderange
    assert_equal("aaa", str.str_conv_enc_opts("UTF-16LE", "UTF-8", 0, nil))
  end
end
