require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/quo'

describe "Numeric#quo" do
  it "returns the result of self divided by the given Integer as a Rational" do
    5.quo(2).should eql(Rational(5,2))
  end

  it "returns the result of self divided by the given Float as a Float" do
    2.quo(2.5).should eql(0.8)
  end

  it "returns the result of self divided by the given Bignum as a Float" do
    45.quo(bignum_value).should be_close(1.04773789668636e-08, TOLERANCE)
  end

  it "raises a ZeroDivisionError when the given Integer is 0" do
    -> { 0.quo(0) }.should raise_error(ZeroDivisionError)
    -> { 10.quo(0) }.should raise_error(ZeroDivisionError)
    -> { -10.quo(0) }.should raise_error(ZeroDivisionError)
    -> { bignum_value.quo(0) }.should raise_error(ZeroDivisionError)
    -> { -bignum_value.quo(0) }.should raise_error(ZeroDivisionError)
  end

  it "calls #to_r to convert the object to a Rational" do
    obj = NumericSpecs::Subclass.new
    obj.should_receive(:to_r).and_return(Rational(1))

    obj.quo(19).should == Rational(1, 19)
  end

  it "raises a TypeError of #to_r does not return a Rational" do
    obj = NumericSpecs::Subclass.new
    obj.should_receive(:to_r).and_return(1)

    -> { obj.quo(19) }.should raise_error(TypeError)
  end

  it "raises a TypeError when given a non-Integer" do
    -> {
      (obj = mock('x')).should_not_receive(:to_int)
      13.quo(obj)
    }.should raise_error(TypeError)
    -> { 13.quo("10")    }.should raise_error(TypeError)
    -> { 13.quo(:symbol) }.should raise_error(TypeError)
  end

  it "returns the result of calling self#/ with other" do
    obj = NumericSpecs::Subclass.new
    obj.should_receive(:to_r).and_return(19.quo(20))

    obj.quo(19).should == 1.quo(20)
  end
end
