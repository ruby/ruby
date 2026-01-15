require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "4.0" do
  describe "Math.log1p" do
    it "calculates Math.log(1 + arg)" do
      Math.log1p(3).should == Math.log(1 + 3)
    end

    it "preserves precision that can be lost otherwise" do
      Math.log1p(1e-16).should be_close(1.0e-16, TOLERANCE)
      Math.log1p(1e-16).should != 0.0
    end

    it "raises an Math::DomainError if the argument is less than 1" do
      -> { Math.log1p(-1-1e-15) }.should raise_error(Math::DomainError, "Numerical argument is out of domain - log1p")
    end

    it "raises a TypeError if the argument cannot be coerced with Float()" do
      -> { Math.log1p("test") }.should raise_error(TypeError, "can't convert String into Float")
    end

    it "raises a TypeError for numerical values passed as string" do
      -> { Math.log1p("10") }.should raise_error(TypeError, "can't convert String into Float")
    end

    it "does not accept a second argument for the base" do
      -> { Math.log1p(9, 3) }.should raise_error(ArgumentError, "wrong number of arguments (given 2, expected 1)")
    end

    it "returns NaN given NaN" do
      Math.log1p(nan_value).nan?.should be_true
    end

    it "raises a TypeError if the argument is nil" do
      -> { Math.log1p(nil) }.should raise_error(TypeError, "can't convert nil into Float")
    end

    it "accepts any argument that can be coerced with Float()" do
      Math.log1p(MathSpecs::Float.new).should be_close(0.6931471805599453, TOLERANCE)
    end
  end

  describe "Math#log1p" do
    it "is accessible as a private instance method" do
      IncludesMath.new.send(:log1p, 4.21).should be_close(1.65057985576528, TOLERANCE)
    end
  end
end
