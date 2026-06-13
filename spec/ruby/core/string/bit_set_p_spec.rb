# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_set?" do
    it "returns true or false for a bit offset in LSB-first order by default" do
      str = "\xAA"
      str.bit_set?(0).should == false
      str.bit_set?(1).should == true
      str.bit_set?(7).should == true
    end

    it "returns true or false for a bit offset in MSB-first order" do
      str = "\xAA"
      str.bit_set?(0, lsb_first: false).should == true
      str.bit_set?(1, lsb_first: false).should == false
      str.bit_set?(7, lsb_first: false).should == false
    end

    it "preserves byte order when using MSB-first order" do
      str = "\x00\x80"
      str.bit_set?(8, lsb_first: false).should == true
    end

    it "returns nil for a bit offset beyond the string" do
      "\x00".bit_set?(8).should == nil
      "".bit_set?(0).should == nil
    end

    it "raises an IndexError for a negative bit offset" do
      -> { "\x00".bit_set?(-1) }.should.raise(IndexError)
    end

    it "raises an ArgumentError for an invalid lsb_first value" do
      -> { "\x00".bit_set?(0, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
