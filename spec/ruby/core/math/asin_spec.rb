require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# arcsine : (-1.0, 1.0) --> (-PI/2, PI/2)
describe "Math.asin" do
  it "returns a float" do
    Math.asin(1).should be_kind_of(Float)
  end

  it "returns the arcsine of the argument" do
    Math.asin(1).should be_close(Math::PI/2, TOLERANCE)
    Math.asin(0).should be_close(0.0, TOLERANCE)
    Math.asin(-1).should be_close(-Math::PI/2, TOLERANCE)
    Math.asin(0.25).should be_close(0.252680255142079, TOLERANCE)
    Math.asin(0.50).should be_close(0.523598775598299, TOLERANCE)
    Math.asin(0.75).should be_close(0.8480620789814816,TOLERANCE)
  end

  it "raises an Math::DomainError if the argument is greater than 1.0" do
    -> { Math.asin(1.0001) }.should raise_error( Math::DomainError)
  end

  it "raises an Math::DomainError if the argument is less than -1.0" do
    -> { Math.asin(-1.0001) }.should raise_error( Math::DomainError)
  end

  it "raises a TypeError if the argument cannot be coerced with Float()" do
    -> { Math.asin("test") }.should raise_error(TypeError)
  end

  it "returns NaN given NaN" do
    Math.asin(nan_value).nan?.should be_true
  end

  it "raises a TypeError if the argument is nil" do
    -> { Math.asin(nil) }.should raise_error(TypeError)
  end

  it "accepts any argument that can be coerced with Float()" do
    Math.asin(MathSpecs::Float.new).should be_close(1.5707963267949, TOLERANCE)
  end
end

describe "Math#asin" do
  it "is accessible as a private instance method" do
    IncludesMath.new.send(:asin, 0.5).should be_close(0.523598775598299, TOLERANCE)
  end
end
