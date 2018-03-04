require_relative '../../spec_helper'

describe "Integer#~" do
  context "fixnum" do
    it "returns self with each bit flipped" do
      (~0).should == -1
      (~1221).should == -1222
      (~-2).should == 1
      (~-599).should == 598
    end
  end

  context "bignum" do
    it "returns self with each bit flipped" do
      (~bignum_value(48)).should == -9223372036854775857
      (~(-bignum_value(21))).should == 9223372036854775828
      (~bignum_value(1)).should == -9223372036854775810
    end
  end
end
