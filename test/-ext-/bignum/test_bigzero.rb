# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestBigZero < Test::Unit::TestCase
    def test_equal_0
      bug8204 = '[ruby-core:53893] [Bug #8204]'
      (0..10).each do |i|
        assert_equal(0, Bug::Bignum.zero(i), "#{bug8204} Bignum.zero(#{i})")
      end
    end
  end
end
