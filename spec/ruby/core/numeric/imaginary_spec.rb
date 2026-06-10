require_relative '../../spec_helper'

describe "Numeric#imaginary" do
  before :each do
    @numbers = [
      20,             # Integer
      398.72,         # Float
      Rational(3, 4), # Rational
      bignum_value, # Bignum
      infinity_value,
      nan_value
    ].map{|n| [n,-n]}.flatten
  end

  it "returns 0" do
    @numbers.each do |number|
      number.imaginary.should == 0
    end
  end

  it "raises an ArgumentError if given any arguments" do
    @numbers.each do |number|
      -> { number.imaginary(number) }.should.raise(ArgumentError)
    end
  end
end
