require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#step" do
    it "returns the original value given to step method" do
      (1..10).step.step.should == 1
      (1..10).step(3).step.should == 3
      (1..10).step(0).step.should == 0

      1.step(10).step.should == 1
      1.step(10, 3).step.should == 3
      1.step(10, 0).step.should == 0
    end
  end
end
