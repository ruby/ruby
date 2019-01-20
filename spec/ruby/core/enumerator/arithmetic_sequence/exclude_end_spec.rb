require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#exclude_end?" do
    context "when created using Numeric#step" do
      it "always returns false" do
        1.step(10).exclude_end?.should == false
        10.step(1).exclude_end?.should == false
      end
    end

    context "when created using Range#step" do
      it "mirrors range.exclude_end?" do
        (1...10).step.exclude_end?.should == true
        (1..10).step.exclude_end?.should == false
      end
    end
  end
end
