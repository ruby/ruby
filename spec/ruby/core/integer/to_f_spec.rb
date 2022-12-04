require_relative '../../spec_helper'

describe "Integer#to_f" do
  context "fixnum" do
    it "returns self converted to a Float" do
      0.to_f.should == 0.0
      -500.to_f.should == -500.0
      9_641_278.to_f.should == 9641278.0
    end
  end

  context "bignum" do
    it "returns self converted to a Float" do
      bignum_value(0x4000_0aa0_0bb0_0000).to_f.should eql(23_058_441_774_644_068_352.0)
      bignum_value(0x8000_0000_0000_0ccc).to_f.should eql(27_670_116_110_564_330_700.0)
      (-bignum_value(99)).to_f.should eql(-18_446_744_073_709_551_715.0)
    end

    it "converts number close to Float::MAX without exceeding MAX or producing NaN" do
      (10**308).to_f.should == 10.0 ** 308
    end
  end
end
