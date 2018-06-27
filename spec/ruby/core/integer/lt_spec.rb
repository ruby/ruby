require_relative '../../spec_helper'
require_relative 'shared/comparison_coerce'

describe "Integer#<" do
  ruby_version_is "2.4"..."2.5" do
    it_behaves_like :integer_comparison_coerce_rescue, :<
  end

  ruby_version_is "2.5" do
    it_behaves_like :integer_comparison_coerce_not_rescue, :<
  end

  context "fixnum" do
    it "returns true if self is less than the given argument" do
      (2 < 13).should == true
      (-600 < -500).should == true

      (5 < 1).should == false
      (5 < 5).should == false

      (900 < bignum_value).should == true
      (5 < 4.999).should == false
    end

    it "raises an ArgumentError when given a non-Integer" do
      lambda { 5 < "4"       }.should raise_error(ArgumentError)
      lambda { 5 < mock('x') }.should raise_error(ArgumentError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(32)
    end

    it "returns true if self is less than the given argument" do
      (@bignum < @bignum + 1).should == true
      (-@bignum < -(@bignum - 1)).should == true

      (@bignum < 1).should == false
      (@bignum < 5).should == false

      (@bignum < 4.999).should == false
    end

    it "raises an ArgumentError when given a non-Integer" do
      lambda { @bignum < "4" }.should raise_error(ArgumentError)
      lambda { @bignum < mock('str') }.should raise_error(ArgumentError)
    end
  end
end
