require_relative '../../spec_helper'

ruby_version_is "2.4" do
  describe "Complex#finite?" do
    it "returns true if magnitude is finite" do
      (1+1i).finite?.should == true
    end

    it "returns false for positive infinity" do
      value = Complex(Float::INFINITY, 42)
      value.finite?.should == false
    end

    it "returns false for positive complex with infinite imaginary" do
      value = Complex(1, Float::INFINITY)
      value.finite?.should == false
    end

    it "returns false for negative infinity" do
      value = -Complex(Float::INFINITY, 42)
      value.finite?.should == false
    end

    it "returns false for negative complex with infinite imaginary" do
      value = -Complex(1, Float::INFINITY)
      value.finite?.should == false
    end

    ruby_bug "#14014", "2.4"..."2.5" do
      it "returns false for NaN" do
        value = Complex(Float::NAN, Float::NAN)
        value.finite?.should == false
      end
    end
  end
end
