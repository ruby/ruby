require_relative '../../spec_helper'
require_relative 'shared/quo'
require 'bigdecimal'

describe "BigDecimal#/" do
  it_behaves_like :bigdecimal_quo, :/, []

  before :each do
    @three = BigDecimal("3")
  end

  describe "with Rational" do
    it "produces a BigDecimal" do
      (@three / Rational(500, 2)).should == BigDecimal("0.12e-1")
    end
  end
end
