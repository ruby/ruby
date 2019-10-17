# frozen_string_literal: false
require 'test/unit'
require "-test-/struct"

class Bug::Struct::Test_Len < Test::Unit::TestCase
  def test_rstruct_len
    klass = Bug::Struct.new(:a, :b, :c)
    assert_equal 3, klass.new.rstruct_len
  end
end
