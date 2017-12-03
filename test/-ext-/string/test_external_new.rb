# frozen_string_literal: false
require 'test/unit'
require '-test-/string'

class Test_StringExternalNew < Test::Unit::TestCase
  def test_buf_new
    assert_operator(0, :<=, Bug::String.capacity(Bug::String.buf_new(0)))
    assert_operator(127, :<=, Bug::String.capacity(Bug::String.buf_new(127)))
    assert_operator(128, :<=, Bug::String.capacity(Bug::String.buf_new(128)))
  end

  def test_external_new_with_enc
    Encoding.list.each do |enc|
      assert_equal(enc, Bug::String.external_new(0, enc).encoding)
    end
  end
end
