require_relative '../../spec_helper'
require 'bigdecimal'

describe "BidDecimal#hash" do
  describe "two BigDecimal objects with the same value" do
    it "should have the same hash for ordinary values" do
      BigDecimal('1.2920').hash.should == BigDecimal('1.2920').hash
    end

    it "should have the same hash for infinite values" do
      BigDecimal("+Infinity").hash.should == BigDecimal("+Infinity").hash
      BigDecimal("-Infinity").hash.should == BigDecimal("-Infinity").hash
    end

    it "should have the same hash for NaNs" do
      BigDecimal("NaN").hash.should == BigDecimal("NaN").hash
    end

    it "should have the same hash for zero values" do
      BigDecimal("+0").hash.should == BigDecimal("+0").hash
      BigDecimal("-0").hash.should == BigDecimal("-0").hash
    end
  end

  describe "two BigDecimal objects with numerically equal values" do
    it "should have the same hash value" do
      BigDecimal("1.2920").hash.should == BigDecimal("1.2920000").hash
    end
  end
end
