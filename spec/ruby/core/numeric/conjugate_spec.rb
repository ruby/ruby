require_relative '../../spec_helper'

describe "Numeric#conjugate" do
  before :each do
    @numbers = [
      20,             # Integer
      398.72,         # Float
      Rational(3, 4), # Rational
      bignum_value,
      infinity_value,
      nan_value
    ]
  end

  it "returns self" do
    @numbers.each do |number|
      number.conjugate.should.equal?(number)
    end
  end
end
