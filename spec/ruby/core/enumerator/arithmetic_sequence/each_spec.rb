require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#each" do
  before :each do
    ScratchPad.record []
    @seq = 1.step(10, 4)
  end

  it "calls given block on each item of the sequence" do
    @seq.each { |item| ScratchPad << item }
    ScratchPad.recorded.should == [1, 5, 9]
  end

  it "returns self" do
    @seq.each { |item| }.should equal(@seq)
  end
end
