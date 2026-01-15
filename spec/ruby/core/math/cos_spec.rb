require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# cosine : (-Inf, Inf) --> (-1.0, 1.0)
describe "Math.cos" do
  it "returns a float" do
    Math.cos(Math::PI).should be_kind_of(Float)
  end

  it "returns the cosine of the argument expressed in radians" do
    Math.cos(Math::PI).should be_close(-1.0, TOLERANCE)
    Math.cos(0).should be_close(1.0, TOLERANCE)
    Math.cos(Math::PI/2).should be_close(0.0, TOLERANCE)
    Math.cos(3*Math::PI/2).should be_close(0.0, TOLERANCE)
    Math.cos(2*Math::PI).should be_close(1.0, TOLERANCE)
  end

  it "raises a TypeError unless the argument is Numeric and has #to_f" do
    -> { Math.cos("test") }.should raise_error(TypeError)
  end

  it "returns NaN given NaN" do
    Math.cos(nan_value).nan?.should be_true
  end

  describe "coerces its argument with #to_f" do
    it "coerces its argument with #to_f" do
      f = mock_numeric('8.2')
      f.should_receive(:to_f).and_return(8.2)
      Math.cos(f).should == Math.cos(8.2)
    end

    it "raises a TypeError if the given argument can't be converted to a Float" do
      -> { Math.cos(nil) }.should raise_error(TypeError)
      -> { Math.cos(:abc) }.should raise_error(TypeError)
    end

    it "raises a NoMethodError if the given argument raises a NoMethodError during type coercion to a Float" do
      object = mock_numeric('mock-float')
      object.should_receive(:to_f).and_raise(NoMethodError)
      -> { Math.cos(object) }.should raise_error(NoMethodError)
    end
  end
end

describe "Math#cos" do
  it "is accessible as a private instance method" do
    IncludesMath.new.send(:cos, 3.1415).should be_close(-0.999999995707656, TOLERANCE)
  end
end
