# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_get" do
    it "returns 0 or 1 for a bit offset in LSB-first order by default" do
      str = "\xAA"
      str.bit_get(0).should == 0
      str.bit_get(1).should == 1
      str.bit_get(7).should == 1
    end

    it "returns 0 or 1 for a bit offset in MSB-first order" do
      str = "\xAA"
      str.bit_get(0, lsb_first: false).should == 1
      str.bit_get(1, lsb_first: false).should == 0
      str.bit_get(7, lsb_first: false).should == 0
    end

    it "preserves byte order when using MSB-first order" do
      str = "\x00\x80"
      str.bit_get(8, lsb_first: false).should == 1
    end

    it "returns nil for a bit offset beyond the string" do
      "\x00".bit_get(8).should == nil
      "".bit_get(0).should == nil
    end

    it "raises an IndexError for a negative bit offset" do
      -> { "\x00".bit_get(-1) }.should.raise(IndexError)
    end

    it "raises an ArgumentError for an invalid lsb_first value" do
      -> { "\x00".bit_get(0, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
