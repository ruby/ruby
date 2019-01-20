require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#size" do
    context "for finite sequence" do
      it "returns the number of elements in this arithmetic sequence" do
        1.step(10).size.should == 10
        (1...10).step.size.should == 9
      end
    end

    context "for infinite sequence" do
      it "returns Infinity" do
        1.step(Float::INFINITY).size.should == Float::INFINITY
        (1..Float::INFINITY).step.size.should == Float::INFINITY
      end
    end
  end
end
