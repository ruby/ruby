require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#end" do
    it "returns the end of the sequence" do
      1.step(10).end.should == 10
      (1..10).step.end.should == 10
      (1...10).step(17).end.should == 10
    end
  end
end
