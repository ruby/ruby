require_relative '../../spec_helper'
require_relative 'shared/mult'
require 'bigdecimal'

describe "BigDecimal#*" do
  it_behaves_like :bigdecimal_mult, :*, []
end

describe "BigDecimal#*" do
  before :each do
    @three = BigDecimal("3")
    @e3_minus = BigDecimal("3E-20001")
    @e3_plus = BigDecimal("3E20001")
    @e = BigDecimal("1.00000000000000000000123456789")
    @one = BigDecimal("1")
  end

  it "multiply self with other" do
    (@one * @one).should == @one
    (@e3_minus * @e3_plus).should == BigDecimal("9")
    # Can't do this till we implement **
    # (@e3_minus * @e3_minus).should == @e3_minus ** 2
    # So let's rewrite it as:
    (@e3_minus * @e3_minus).should == BigDecimal("9E-40002")
    (@e * @one).should == @e
  end

  describe "with Object" do
    it "tries to coerce the other operand to self" do
      object = mock("Object")
      object.should_receive(:coerce).with(@e3_minus).and_return([@e3_minus, @e3_plus])
      (@e3_minus * object).should == BigDecimal("9")
    end
  end

  describe "with Rational" do
    it "produces a BigDecimal" do
      (@three * Rational(500, 2)).should == BigDecimal("0.75e3")
    end
  end
end
