require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#sub" do

  before :each do
    @one = BigDecimal("1")
    @zero = BigDecimal("0")
    @two = BigDecimal("2")
    @three = BigDecimal("3")
    @nan = BigDecimal("NaN")
    @infinity = BigDecimal("Infinity")
    @infinity_minus = BigDecimal("-Infinity")
    @one_minus = BigDecimal("-1")
    @frac_1 = BigDecimal("1E-99999")
    @frac_2 = BigDecimal("0.9E-99999")
    @frac_3 = BigDecimal("12345E10")
    @frac_4 = BigDecimal("98765E10")
  end

  it "returns a - b with given precision" do
    # documentation states, that precision is optional
    # but implementation raises ArgumentError if not given.

    @two.sub(@one, 1).should == @one
    @one.sub(@two, 1).should == @one_minus
    @one.sub(@one_minus, 1).should == @two
    @frac_2.sub(@frac_1, 1000000).should == BigDecimal("-0.1E-99999")
    @frac_2.sub(@frac_1, 1).should == BigDecimal("-0.1E-99999")
    # the above two examples puzzle me.
    in_arow_one = BigDecimal("1.23456789")
    in_arow_two = BigDecimal("1.2345678")
    in_arow_one.sub(in_arow_two, 10).should == BigDecimal("0.9E-7")
    @two.sub(@two,1).should == @zero
    @frac_1.sub(@frac_1, 1000000).should == @zero
  end

  describe "with Object" do
    it "tries to coerce the other operand to self" do
      object = mock("Object")
      object.should_receive(:coerce).with(@frac_3).and_return([@frac_3, @frac_4])
      @frac_3.sub(object, 1).should == BigDecimal("-0.9E15")
    end
  end

  describe "with Rational" do
    it "produces a BigDecimal" do
      (@three - Rational(500, 2)).should == BigDecimal('-0.247e3')
    end
  end

  it "returns NaN if NaN is involved" do
    @one.sub(@nan, 1).nan?.should == true
    @nan.sub(@one, 1).nan?.should == true
  end

  it "returns NaN if both values are infinite with the same signs" do
    @infinity.sub(@infinity, 1).nan?.should == true
    @infinity_minus.sub(@infinity_minus, 1).nan?.should == true
  end

  it "returns Infinity or -Infinity if these are involved" do
    @infinity.sub(@infinity_minus, 1).should == @infinity
    @infinity_minus.sub(@infinity, 1).should == @infinity_minus
    @zero.sub(@infinity, 1).should == @infinity_minus
    @frac_2.sub( @infinity, 1).should == @infinity_minus
    @two.sub(@infinity, 1).should == @infinity_minus
  end

end
