require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Math.acosh" do
  it "returns a float" do
    Math.acosh(1.0).should be_kind_of(Float)
  end

  it "returns the principle value of the inverse hyperbolic cosine of the argument" do
    Math.acosh(14.2).should be_close(3.345146999647, TOLERANCE)
    Math.acosh(1.0).should be_close(0.0, TOLERANCE)
  end

  it "raises Math::DomainError if the passed argument is less than -1.0 or greater than 1.0" do
    -> { Math.acosh(1.0 - TOLERANCE) }.should raise_error(Math::DomainError)
    -> { Math.acosh(0) }.should raise_error(Math::DomainError)
    -> { Math.acosh(-1.0) }.should raise_error(Math::DomainError)
  end

  it "raises a TypeError if the argument cannot be coerced with Float()" do
    -> { Math.acosh("test") }.should raise_error(TypeError)
  end

  it "returns NaN given NaN" do
    Math.acosh(nan_value).nan?.should be_true
  end

  it "raises a TypeError if the argument is nil" do
    -> { Math.acosh(nil) }.should raise_error(TypeError)
  end

  it "accepts any argument that can be coerced with Float()" do
    Math.acosh(MathSpecs::Float.new).should == 0.0
  end
end

describe "Math#acosh" do
  it "is accessible as a private instance method" do
    IncludesMath.new.send(:acosh, 1.0).should be_close(0.0, TOLERANCE)
  end
end
