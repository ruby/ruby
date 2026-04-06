require_relative '../../spec_helper'

describe "Integer#eql?" do
  context "bignum" do
    it "returns true for the same value" do
      bignum_value.eql?(bignum_value).should == true
    end

    it "returns false for a different Integer value" do
      bignum_value.eql?(bignum_value(1)).should == false
    end

    it "returns false for a Float with the same numeric value" do
      bignum_value.eql?(bignum_value.to_f).should == false
    end

    it "returns false for a Rational with the same numeric value" do
      bignum_value.eql?(Rational(bignum_value)).should == false
    end

    it "returns false for a Fixnum-range Integer" do
      bignum_value.eql?(42).should == false
    end
  end
end
