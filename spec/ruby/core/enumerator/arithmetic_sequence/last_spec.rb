require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#last" do
  it "returns the last element of the sequence" do
    1.step(10).last.should == 10
    (1..10).step.last.should == 10
    (1...10).step(4).last.should == 9
  end
end
