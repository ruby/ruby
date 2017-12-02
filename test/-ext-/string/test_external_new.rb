# frozen_string_literal: false
require 'test/unit'
require '-test-/string'

class Test_StringExternalNew < Test::Unit::TestCase
  def test_external_new_with_enc
    Encoding.list.each do |enc|
      assert_equal(enc, Bug::String.external_new(0, enc).encoding)
    end
  end
end
