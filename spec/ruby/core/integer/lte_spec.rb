require_relative '../../spec_helper'
require_relative 'shared/comparison_coerce'

describe "Integer#<=" do
  it_behaves_like :integer_comparison_coerce_not_rescue, :<=

  context "fixnum" do
    it "returns true if self is less than or equal to other" do
      (2 <= 13).should == true
      (-600 <= -500).should == true

      (5 <= 1).should == false
      (5 <= 5).should == true
      (-2 <= -2).should == true

      (900 <= bignum_value).should == true
      (5 <= 4.999).should == false
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { 5 <= "4"       }.should raise_error(ArgumentError)
      -> { 5 <= mock('x') }.should raise_error(ArgumentError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(39)
    end

    it "returns true if self is less than or equal to other" do
      (@bignum <= @bignum).should == true
      (-@bignum <= -(@bignum - 1)).should == true

      (@bignum <= 4.999).should == false
    end

    it "returns false if compares with near float" do
      (@bignum <= (@bignum + 0.0)).should == false
      (@bignum <= (@bignum + 0.5)).should == false
    end

    it "returns true for bignums compare to a bigger float" do
      (18446744073709551616 <= 1.8446744073709552e+19).should == true
      (@bignum <= (@bignum + 9999.0)).should == true
    end

    it "raises an ArgumentError when given a non-Integer" do
      -> { @bignum <= "4" }.should raise_error(ArgumentError)
      -> { @bignum <= mock('str') }.should raise_error(ArgumentError)
    end
  end
end
