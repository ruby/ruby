require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is "2.4" do
  describe "Complex#infinite?" do
    it "returns nil if magnitude is finite" do
      (1+1i).infinite?.should == nil
    end

    it "returns 1 for positive infinity" do
      value = Complex(Float::INFINITY, 42).infinite?
      value.should == 1
    end

    it "returns 1 for positive complex with infinite imaginary" do
      value = Complex(1, Float::INFINITY).infinite?
      value.should == 1
    end

    it "returns -1 for negative infinity" do
      value = -Complex(Float::INFINITY, 42).infinite?
      value.should == -1
    end

    it "returns -1 for negative complex with infinite imaginary" do
      value = -Complex(1, Float::INFINITY).infinite?
      value.should == -1
    end

    it "returns nil for NaN" do
      value = Complex(0, Float::NAN).infinite?
      value.should == nil
    end
  end
end
