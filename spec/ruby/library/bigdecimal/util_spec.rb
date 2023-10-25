require_relative '../../spec_helper'
require 'bigdecimal'
require 'bigdecimal/util'

describe "BigDecimal's util method definitions" do
  describe "#to_d" do
    it "should define #to_d on Integer" do
      42.to_d.should == BigDecimal(42)
    end

    it "should define #to_d on Float" do
      0.5.to_d.should == BigDecimal(0.5, Float::DIG)
      1.234.to_d(2).should == BigDecimal(1.234, 2)
    end

    it "should define #to_d on String" do
      "0.5".to_d.should == BigDecimal(0.5, Float::DIG)
      "45.67 degrees".to_d.should == BigDecimal(45.67, Float::DIG)
    end

    it "should define #to_d on BigDecimal" do
      bd = BigDecimal("3.14")
      bd.to_d.should equal(bd)
    end

    it "should define #to_d on Rational" do
      Rational(22, 7).to_d(3).should == BigDecimal(3.14, 3)
    end

    it "should define #to_d on nil" do
      nil.to_d.should == BigDecimal(0)
    end
  end

  describe "#to_digits" do
    it "should define #to_digits on BigDecimal" do
      BigDecimal("3.14").to_digits.should == "3.14"
    end
  end
end
