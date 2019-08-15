require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#==" do
    it "returns true if begin, end, step and exclude_end? are equal" do
      1.step(10).should == 1.step(10)
      1.step(10, 5).should == 1.step(10, 5)

      (1..10).step.should == (1..10).step
      (1...10).step(8).should == (1...10).step(8)

      # both have exclude_end? == false
      (1..10).step(100).should == 1.step(10, 100)

      ((1..10).step == (1..11).step).should == false
      ((1..10).step == (1...10).step).should == false
      ((1..10).step == (1..10).step(2)).should == false
    end
  end
end
