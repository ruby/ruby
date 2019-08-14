require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#first" do
    it "returns the first element of the sequence" do
      1.step(10).first.should == 1
      (1..10).step.first.should == 1
      (1...10).step.first.should == 1
    end
  end
end
