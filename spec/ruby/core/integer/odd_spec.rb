require_relative '../../spec_helper'

describe "Integer#odd?" do
  context "fixnum" do
    it "returns true when self is an odd number" do
      (-2).odd?.should == false
      (-1).odd?.should == true

      0.odd?.should == false
      1.odd?.should == true
      2.odd?.should == false

      bignum_value(0).odd?.should == false
      bignum_value(1).odd?.should == true

      (-bignum_value(0)).odd?.should == false
      (-bignum_value(1)).odd?.should == true
    end
  end

  context "bignum" do
    it "returns true if self is odd and positive" do
      (987279**19).odd?.should == true
    end

    it "returns true if self is odd and negative" do
      (-9873389**97).odd?.should == true
    end

    it "returns false if self is even and positive" do
      (10000000**10).odd?.should == false
    end

    it "returns false if self is even and negative" do
      (-1000000**100).odd?.should == false
    end
  end
end
