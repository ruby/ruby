require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal constants" do
  ruby_version_is "2.5" do
    it "defines a VERSION value" do
      BigDecimal.const_defined?(:VERSION).should be_true
    end
  end

  it "has a BASE value" do
    # The actual one is decided based on HAVE_INT64_T in MRI,
    # which is hard to check here.
    [10000, 1000000000].should include(BigDecimal::BASE)
  end

  it "has a NaN value" do
    BigDecimal::NAN.nan?.should be_true
  end

  it "has an INFINITY value" do
    BigDecimal::INFINITY.infinite?.should == 1
  end

  describe "exception-related constants" do
    [
      [:EXCEPTION_ALL, 0xff],
      [:EXCEPTION_INFINITY, 0x01],
      [:EXCEPTION_NaN, 0x02],
      [:EXCEPTION_UNDERFLOW, 0x04],
      [:EXCEPTION_OVERFLOW, 0x01],
      [:EXCEPTION_ZERODIVIDE, 0x10]
    ].each do |const, value|
      it "has a #{const} value" do
        BigDecimal.const_get(const).should == value
      end
    end
  end

  describe "rounding-related constants" do
    [
      [:ROUND_MODE, 0x100],
      [:ROUND_UP, 1],
      [:ROUND_DOWN, 2],
      [:ROUND_HALF_UP, 3],
      [:ROUND_HALF_DOWN, 4],
      [:ROUND_CEILING, 5],
      [:ROUND_FLOOR, 6],
      [:ROUND_HALF_EVEN, 7]
    ].each do |const, value|
      it "has a #{const} value" do
        BigDecimal.const_get(const).should == value
      end
    end
  end

  describe "sign-related constants" do
    [
      [:SIGN_NaN, 0],
      [:SIGN_POSITIVE_ZERO, 1],
      [:SIGN_NEGATIVE_ZERO, -1],
      [:SIGN_POSITIVE_FINITE, 2],
      [:SIGN_NEGATIVE_FINITE, -2],
      [:SIGN_POSITIVE_INFINITE, 3],
      [:SIGN_NEGATIVE_INFINITE, -3]
    ].each do |const, value|
      it "has a #{const} value" do
        BigDecimal.const_get(const).should == value
      end
    end
  end
end
