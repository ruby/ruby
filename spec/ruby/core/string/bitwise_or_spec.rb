# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bitwise_or" do
    it "returns a new string containing the byte-wise OR with another string" do
      str = "\xF0"
      result = str.bitwise_or("\x0C")
      result.should == "\xFC".b
      result.should_not.equal?(str)
      str.should == "\xF0"
    end

    it "converts the argument with to_str" do
      other = mock("string")
      other.should_receive(:to_str).and_return("\x0C")
      "\xF0".bitwise_or(other).should == "\xFC".b
    end

    it "raises an ArgumentError if byte sizes differ" do
      -> { "\x00".bitwise_or("\x00\x00") }.should.raise(ArgumentError)
    end

    it "returns a BINARY string" do
      "\xF0".dup.force_encoding("UTF-8").bitwise_or("\x0C").encoding.should == Encoding::BINARY
    end
  end

  describe "String#bitwise_or!" do
    it "replaces self with the byte-wise OR and returns self" do
      str = "\xF0".dup
      str.bitwise_or!("\x0C").should.equal?(str)
      str.should == "\xFC"
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bitwise_or!("\x00") }.should.raise(FrozenError)
    end
  end
end
