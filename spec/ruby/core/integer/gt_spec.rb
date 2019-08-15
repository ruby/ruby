require_relative '../../spec_helper'
require_relative 'shared/comparison_coerce'

describe "Integer#>" do
  ruby_version_is "2.4"..."2.5" do
    it_behaves_like :integer_comparison_coerce_rescue, :>
  end

  ruby_version_is "2.5" do
    it_behaves_like :integer_comparison_coerce_not_rescue, :>
  end

  context "fixnum" do
    it "returns true if self is greater than the given argument" do
      (13 > 2).should == true
      (-500 > -600).should == true

      (1 > 5).should == false
      (5 > 5).should == false

      (900 > bignum_value).should == false
      (5 > 4.999).should == true
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { 5 > "4"       }.should raise_error(ArgumentError)
      -> { 5 > mock('x') }.should raise_error(ArgumentError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(732)
    end

    it "returns true if self is greater than the given argument" do
      (@bignum > (@bignum - 1)).should == true
      (@bignum > 14.6).should == true
      (@bignum > 10).should == true

      (@bignum > (@bignum + 500)).should == false
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { @bignum > "4" }.should raise_error(ArgumentError)
      -> { @bignum > mock('str') }.should raise_error(ArgumentError)
    end
  end
end
