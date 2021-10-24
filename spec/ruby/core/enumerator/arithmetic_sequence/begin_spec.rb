require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#begin" do
  it "returns the begin of the sequence" do
    1.step(10).begin.should == 1
    (1..10).step.begin.should == 1
    (1...10).step.begin.should == 1
  end
end
