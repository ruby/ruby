require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# The natural logarithm, having base Math::E
describe "Math.log" do
  it "returns a float" do
    Math.log(1).should be_kind_of(Float)
  end

  it "returns the natural logarithm of the argument" do
    Math.log(0.0001).should be_close(-9.21034037197618, TOLERANCE)
    Math.log(0.000000000001e-15).should be_close(-62.1697975108392, TOLERANCE)
    Math.log(1).should be_close(0.0, TOLERANCE)
    Math.log(10).should be_close( 2.30258509299405, TOLERANCE)
    Math.log(10e15).should be_close(36.8413614879047, TOLERANCE)
  end

  it "raises an Math::DomainError if the argument is less than 0" do
    -> { Math.log(-1e-15) }.should raise_error(Math::DomainError)
  end

  it "raises a TypeError if the argument cannot be coerced with Float()" do
    -> { Math.log("test") }.should raise_error(TypeError)
  end

  it "raises a TypeError for numerical values passed as string" do
    -> { Math.log("10") }.should raise_error(TypeError)
  end

  it "accepts a second argument for the base" do
    Math.log(9, 3).should be_close(2, TOLERANCE)
    Math.log(8, 1.4142135623730951).should be_close(6, TOLERANCE)
  end

  it "raises a TypeError when the numerical base cannot be coerced to a float" do
    -> { Math.log(10, "2") }.should raise_error(TypeError)
    -> { Math.log(10, nil) }.should raise_error(TypeError)
  end

  it "returns NaN given NaN" do
    Math.log(nan_value).nan?.should be_true
  end

  it "raises a TypeError if the argument is nil" do
    -> { Math.log(nil) }.should raise_error(TypeError)
  end

  it "accepts any argument that can be coerced with Float()" do
    Math.log(MathSpecs::Float.new).should be_close(0.0, TOLERANCE)
  end
end

describe "Math#log" do
  it "is accessible as a private instance method" do
    IncludesMath.new.send(:log, 5.21).should be_close(1.65057985576528, TOLERANCE)
  end
end
