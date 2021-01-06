# frozen_string_literal: true
require_relative "testbase"

class TestBigDecimalRactor < Test::Unit::TestCase
  include TestBigDecimalBase

  def setup
    super
    skip unless defined? Ractor
  end

  def test_ractor_shareable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      require "bigdecimal"
      r = Ractor.new BigDecimal(Math::PI, Float::DIG+1) do |pi|
        BigDecimal('2.0')*pi
      end
      assert_equal(2*Math::PI, r.take)
    end;
  end
end
