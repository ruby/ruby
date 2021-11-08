require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#step" do
  it "returns the original value given to step method" do
    (1..10).step.step.should == 1
    (1..10).step(3).step.should == 3

    1.step(10).step.should == 1
    1.step(10, 3).step.should == 3
  end
end
