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
end
