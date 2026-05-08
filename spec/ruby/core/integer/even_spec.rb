require_relative '../../spec_helper'

describe "Integer#even?" do
  context "fixnum" do
    it "returns true for a Fixnum when it is an even number" do
      (-2).even?.should == true
      (-1).even?.should == false

      0.even?.should == true
      1.even?.should == false
      2.even?.should == true
    end

    it "returns true for a Bignum when it is an even number" do
      bignum_value(0).even?.should == true
      bignum_value(1).even?.should == false

      (-bignum_value(0)).even?.should == true
      (-bignum_value(1)).even?.should == false
    end
  end

  context "bignum" do
    it "returns true if self is even and positive" do
      (10000**10).even?.should == true
    end

    it "returns true if self is even and negative" do
      (-10000**10).even?.should == true
    end

    it "returns false if self is odd and positive" do
      (9879**976).even?.should == false
    end

    it "returns false if self is odd and negative" do
      (-9879**976).even?.should == false
    end
  end
end
