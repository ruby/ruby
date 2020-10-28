require_relative '../../spec_helper'
require_relative 'shared/comparison_coerce'

describe "Integer#>=" do
  it_behaves_like :integer_comparison_coerce_not_rescue, :>=

  context "fixnum" do
    it "returns true if self is greater than or equal to the given argument" do
      (13 >= 2).should == true
      (-500 >= -600).should == true

      (1 >= 5).should == false
      (2 >= 2).should == true
      (5 >= 5).should == true

      (900 >= bignum_value).should == false
      (5 >= 4.999).should == true
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { 5 >= "4"       }.should raise_error(ArgumentError)
      -> { 5 >= mock('x') }.should raise_error(ArgumentError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(14)
    end

    it "returns true if self is greater than or equal to other" do
      (@bignum >= @bignum).should == true
      (@bignum >= (@bignum + 2)).should == false
      (@bignum >= 5664.2).should == true
      (@bignum >= 4).should == true
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { @bignum >= "4" }.should raise_error(ArgumentError)
      -> { @bignum >= mock('str') }.should raise_error(ArgumentError)
    end
  end
end
