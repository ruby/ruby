require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#end" do
  it "returns the end of the sequence" do
    1.step(10).end.should == 10
    (1..10).step.end.should == 10
    (1...10).step(17).end.should == 10
  end

  context "with endless" do
    it "returns nil as end of the sequence" do
      (1..).step(1).end.should == nil
      (1...).step(1).end.should == nil
    end
  end
end
