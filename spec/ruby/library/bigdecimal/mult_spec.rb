require_relative '../../spec_helper'
require_relative 'shared/mult'
require 'bigdecimal'

describe "BigDecimal#mult" do
  it_behaves_like :bigdecimal_mult, :mult, [10]
end

describe "BigDecimal#mult" do
  before :each do
    @one = BigDecimal "1"
    @e3_minus = BigDecimal("3E-20001")
    @e3_plus = BigDecimal("3E20001")
    @e = BigDecimal "1.00000000000000000000123456789"
    @tolerance = @e.sub @one, 1000
    @tolerance2 = BigDecimal "30001E-20005"

  end

  it "multiply self with other with (optional) precision" do
    @e.mult(@one, 1).should be_close(@one, @tolerance)
    @e3_minus.mult(@one, 1).should be_close(0, @tolerance2)
  end

  describe "with Object" do
    it "tries to coerce the other operand to self" do
      object = mock("Object")
      object.should_receive(:coerce).with(@e3_minus).and_return([@e3_minus, @e3_plus])
      @e3_minus.mult(object, 1).should == BigDecimal("9")
    end
  end
end
