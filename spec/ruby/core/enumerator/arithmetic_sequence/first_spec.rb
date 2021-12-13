require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#first" do
  it "returns the first element of the sequence" do
    1.step(10).first.should == 1
    (1..10).step.first.should == 1
    (1...10).step.first.should == 1
  end
end
