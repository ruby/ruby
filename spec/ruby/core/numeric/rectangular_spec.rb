require_relative '../../spec_helper'

describe "Numeric#rectangular" do
  before :each do
    @numbers = [
      20,             # Integer
      398.72,         # Float
      Rational(3, 4), # Rational
      99999999**99, # Bignum
      infinity_value,
      nan_value
    ]
  end

  it "returns an Array" do
    @numbers.each do |number|
      number.rectangular.should.instance_of?(Array)
    end
  end

  it "returns a two-element Array" do
    @numbers.each do |number|
      number.rectangular.size.should == 2
    end
  end

  it "returns self as the first element" do
    @numbers.each do |number|
      if Float === number and number.nan?
        number.rectangular.first.nan?.should == true
      else
        number.rectangular.first.should == number
      end
    end
  end

  it "returns 0 as the last element" do
    @numbers.each do |number|
      number.rectangular.last.should == 0
    end
  end

  it "raises an ArgumentError if given any arguments" do
    @numbers.each do |number|
      -> { number.rectangular(number) }.should.raise(ArgumentError)
    end
  end
end
