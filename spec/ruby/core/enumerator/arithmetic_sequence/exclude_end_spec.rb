require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence#exclude_end?" do
  context "when created using Numeric#step" do
    it "always returns false" do
      1.step(10).should_not.exclude_end?
      10.step(1).should_not.exclude_end?
    end
  end

  context "when created using Range#step" do
    it "mirrors range.exclude_end?" do
      (1...10).step.should.exclude_end?
      (1..10).step.should_not.exclude_end?
    end
  end
end
