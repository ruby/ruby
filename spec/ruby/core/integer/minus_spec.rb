require_relative '../../spec_helper'
require_relative 'shared/arithmetic_coerce'

describe "Integer#-" do
  it_behaves_like :integer_arithmetic_coerce_not_rescue, :-

  context "fixnum" do
    it "returns self minus the given Integer" do
      (5 - 10).should == -5
      (9237212 - 5_280).should == 9231932

      (781 - 0.5).should == 780.5
      (2_560_496 - bignum_value).should == -18446744073706991120
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13 - obj
      }.should raise_error(TypeError)
      -> { 13 - "10"    }.should raise_error(TypeError)
      -> { 13 - :symbol }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(314)
    end

    it "returns self minus the given Integer" do
      (@bignum - 9).should == 18446744073709551921
      (@bignum - 12.57).should be_close(18446744073709551917.43, TOLERANCE)
      (@bignum - bignum_value(42)).should == 272
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum - mock('10') }.should raise_error(TypeError)
      -> { @bignum - "10" }.should raise_error(TypeError)
      -> { @bignum - :symbol }.should raise_error(TypeError)
    end
  end
end
