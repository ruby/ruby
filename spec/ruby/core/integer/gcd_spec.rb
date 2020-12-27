require_relative '../../spec_helper'

describe "Integer#gcd" do
  it "returns self if equal to the argument" do
    1.gcd(1).should == 1
    398.gcd(398).should == 398
  end

  it "returns an Integer" do
    36.gcd(6).should be_kind_of(Integer)
    4.gcd(20981).should be_kind_of(Integer)
  end

  it "returns the greatest common divisor of self and argument" do
    10.gcd(5).should == 5
    200.gcd(20).should == 20
  end

  it "returns a positive integer even if self is negative" do
    -12.gcd(6).should == 6
    -100.gcd(100).should == 100
  end

  it "returns a positive integer even if the argument is negative" do
    12.gcd(-6).should == 6
    100.gcd(-100).should == 100
  end

  it "returns a positive integer even if both self and argument are negative" do
    -12.gcd(-6).should == 6
    -100.gcd(-100).should == 100
  end

  it "accepts a Bignum argument" do
    bignum = 9999**99
    bignum.should be_kind_of(Integer)
    99.gcd(bignum).should == 99
  end

  it "works if self is a Bignum" do
    bignum = 9999**99
    bignum.should be_kind_of(Integer)
    bignum.gcd(99).should == 99
  end

  it "doesn't cause an integer overflow" do
    [2 ** (1.size * 8 - 2), 0x8000000000000000].each do |max|
      [max - 1, max, max + 1].each do |num|
        num.gcd(num).should == num
        (-num).gcd(num).should == num
        (-num).gcd(-num).should == num
        num.gcd(-num).should == num
      end
    end
  end

  it "raises an ArgumentError if not given an argument" do
    -> { 12.gcd }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if given more than one argument" do
    -> { 12.gcd(30, 20) }.should raise_error(ArgumentError)
  end

  it "raises a TypeError unless the argument is an Integer" do
    -> { 39.gcd(3.8)   }.should raise_error(TypeError)
    -> { 45872.gcd([]) }.should raise_error(TypeError)
  end
end
