require_relative '../../spec_helper'
require_relative 'shared/arithmetic_coerce'

describe "Integer#/" do
  it_behaves_like :integer_arithmetic_coerce_not_rescue, :/

  context "fixnum" do
    it "returns self divided by the given argument" do
      (2 / 2).should == 1
      (3 / 2).should == 1
    end

    it "supports dividing negative numbers" do
      (-1 / 10).should == -1
    end

    it "returns result the same class as the argument" do
      (3 / 2).should == 1
      (3 / 2.0).should == 1.5
      (3 / Rational(2, 1)).should == Rational(3, 2)
    end

    it "raises a ZeroDivisionError if the given argument is zero and not a Float" do
      -> { 1 / 0 }.should raise_error(ZeroDivisionError)
    end

    it "does NOT raise ZeroDivisionError if the given argument is zero and is a Float" do
      (1 / 0.0).to_s.should == 'Infinity'
      (-1 / 0.0).to_s.should == '-Infinity'
    end

    it "coerces fixnum and return self divided by other" do
      (-1 / 50.4).should be_close(-0.0198412698412698, TOLERANCE)
      (1 / bignum_value).should == 0
    end

    it "raises a TypeError when given a non-Integer" do
      -> { 13 / mock('10') }.should raise_error(TypeError)
      -> { 13 / "10"       }.should raise_error(TypeError)
      -> { 13 / :symbol    }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(88)
    end

    it "returns self divided by other" do
      (@bignum / 4).should == 2305843009213693974

      (@bignum / bignum_value(2)).should == 1

      (-(10**50) / -(10**40 + 1)).should == 9999999999
      ((10**50) / (10**40 + 1)).should == 9999999999

      ((-10**50) / (10**40 + 1)).should == -10000000000
      ((10**50) / -(10**40 + 1)).should == -10000000000
    end

    it "returns self divided by Float" do
      not_supported_on :opal do
        (bignum_value(88) / 4294967295.0).should be_close(2147483648.5, TOLERANCE)
      end
      (bignum_value(88) / 4294967295.5).should be_close(2147483648.25, TOLERANCE)
    end

    it "returns result the same class as the argument" do
      (@bignum / 4).should == 2305843009213693974
      (@bignum / 4.0).should be_close(2305843009213693974, TOLERANCE)
      (@bignum / Rational(4, 1)).should == Rational(2305843009213693974, 1)
    end

    it "does NOT raise ZeroDivisionError if other is zero and is a Float" do
      (bignum_value / 0.0).to_s.should == 'Infinity'
      (bignum_value / -0.0).to_s.should == '-Infinity'
    end

    it "raises a ZeroDivisionError if other is zero and not a Float" do
      -> { @bignum / 0 }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-numeric" do
      -> { @bignum / mock('10') }.should raise_error(TypeError)
      -> { @bignum / "2" }.should raise_error(TypeError)
      -> { @bignum / :symbol }.should raise_error(TypeError)
    end
  end
end
