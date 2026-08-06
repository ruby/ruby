# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_count" do
    it "returns the number of set bits in the string" do
      "".bit_count.should == 0
      "\x00".bit_count.should == 0
      "\xFF".bit_count.should == 8
      "\xAA\xF0".bit_count.should == 8
    end

    it "raises an ArgumentError when given an argument" do
      -> { "\x00".bit_count(0) }.should.raise(ArgumentError)
      -> { "\x00".bit_count(lsb_first: false) }.should.raise(ArgumentError)
    end
  end
end
