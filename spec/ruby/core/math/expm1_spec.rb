require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "4.0" do
  describe "Math.expm1" do
    it "calculates Math.exp(arg) - 1" do
      Math.expm1(3).should == Math.exp(3) - 1
    end

    it "preserves precision that can be lost otherwise" do
      Math.expm1(1.0e-16).should be_close(1.0e-16, TOLERANCE)
      Math.expm1(1.0e-16).should != 0.0
    end

    it "raises a TypeError if the argument cannot be coerced with Float()" do
      -> { Math.expm1("test") }.should raise_error(TypeError, "can't convert String into Float")
    end

    it "returns NaN given NaN" do
      Math.expm1(nan_value).nan?.should be_true
    end

    it "raises a TypeError if the argument is nil" do
      -> { Math.expm1(nil) }.should raise_error(TypeError, "can't convert nil into Float")
    end

    it "accepts any argument that can be coerced with Float()" do
      Math.expm1(MathSpecs::Float.new).should be_close(Math::E - 1, TOLERANCE)
    end
  end

  describe "Math#expm1" do
    it "is accessible as a private instance method" do
      IncludesMath.new.send(:expm1, 23.1415).should be_close(11226018483.0012, TOLERANCE)
    end
  end
end
