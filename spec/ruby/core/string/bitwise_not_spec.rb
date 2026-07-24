# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bitwise_not" do
    it "returns a new string with every bit inverted" do
      str = "\x00\xAA"
      result = str.bitwise_not
      result.should == "\xFF\x55".b
      result.should_not.equal?(str)
      str.should == "\x00\xAA"
    end

    it "returns a BINARY string" do
      str = "\x00".dup.force_encoding("US-ASCII")
      str.bitwise_not.encoding.should == Encoding::BINARY
    end
  end

  describe "String#bitwise_not!" do
    it "inverts every bit in self and returns self" do
      str = "\x00\xAA".dup
      str.bitwise_not!.should.equal?(str)
      str.should == "\xFF\x55"
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bitwise_not! }.should.raise(FrozenError)
    end
  end
end
