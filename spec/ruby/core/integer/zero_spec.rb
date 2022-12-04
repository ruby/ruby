require_relative '../../spec_helper'

describe "Integer#zero?" do
  it "returns true if self is 0" do
    0.should.zero?
    1.should_not.zero?
    -1.should_not.zero?
  end

  ruby_version_is "3.0" do
    it "Integer#zero? overrides Numeric#zero?" do
      42.method(:zero?).owner.should == Integer
    end
  end

  ruby_version_is ""..."3.0" do
    it "Integer#zero? uses Numeric#zero?" do
      42.method(:zero?).owner.should == Numeric
    end
  end
end
