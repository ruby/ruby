require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Math.ldexp" do
  it "returns a float" do
    Math.ldexp(1.0, 2).should be_kind_of(Float)
  end

  it "returns the argument multiplied by 2**n" do
    Math.ldexp(0.0, 0.0).should == 0.0
    Math.ldexp(0.0, 1.0).should == 0.0
    Math.ldexp(-1.25, 2).should be_close(-5.0, TOLERANCE)
    Math.ldexp(2.1, -3).should be_close(0.2625, TOLERANCE)
    Math.ldexp(5.7, 4).should be_close(91.2, TOLERANCE)
  end

  it "raises a TypeError if the first argument cannot be coerced with Float()" do
    -> { Math.ldexp("test", 2) }.should raise_error(TypeError)
  end

  it "returns NaN given NaN" do
    Math.ldexp(nan_value, 0).nan?.should be_true
  end

  it "raises RangeError if NaN is given as the second arg" do
    -> { Math.ldexp(0, nan_value) }.should raise_error(RangeError)
  end

  it "raises a TypeError if the second argument cannot be coerced with Integer()" do
    -> { Math.ldexp(3.2, "this") }.should raise_error(TypeError)
  end

  it "raises a TypeError if the first argument is nil" do
    -> { Math.ldexp(nil, 2) }.should raise_error(TypeError)
  end

  it "raises a TypeError if the second argument is nil" do
    -> { Math.ldexp(3.1, nil) }.should raise_error(TypeError)
  end

  it "accepts any first argument that can be coerced with Float()" do
    Math.ldexp(MathSpecs::Float.new, 2).should be_close(4.0, TOLERANCE)
  end

  it "accepts any second argument that can be coerced with Integer()" do
    Math.ldexp(3.23, MathSpecs::Integer.new).should be_close(12.92, TOLERANCE)
  end

  it "returns correct value that closes to the max value of double type" do
    Math.ldexp(0.5122058490966879, 1024).should == 9.207889385574391e+307
    Math.ldexp(0.9999999999999999, 1024).should == 1.7976931348623157e+308
    Math.ldexp(0.99999999999999999, 1024).should == Float::INFINITY
  end
end

describe "Math#ldexp" do
  it "is accessible as a private instance method" do
    IncludesMath.new.send(:ldexp, 3.1415, 2).should be_close(12.566, TOLERANCE)
  end
end
