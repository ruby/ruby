require_relative '../../spec_helper'

describe "Integer#zero?" do
  it "returns true if self is 0" do
    0.should.zero?
    1.should_not.zero?
    -1.should_not.zero?
  end

  it "Integer#zero? overrides Numeric#zero?" do
    42.method(:zero?).owner.should == Integer
  end
end
