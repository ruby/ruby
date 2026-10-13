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

    it "counts the set bits in a region given as offset and length" do
      data = "\xFF\x00\xF0"
      data.bit_count(0, 8).should == 8
      data.bit_count(8, 8).should == 0
      data.bit_count(4, 8).should == 4
    end

    it "counts the set bits in a region given as a Range" do
      data = "\xFF\x00\xF0"
      data.bit_count(0..7).should == 8
      data.bit_count(8...16).should == 0
      data.bit_count(16..).should == 4
    end

    it "clamps a region that extends past the end of the string" do
      data = "\xFF\x00\xF0"
      data.bit_count(16, 100).should == 4
      data.bit_count(100, 8).should == 0
    end

    it "interprets a non-byte-aligned region according to lsb_first" do
      "\xF0".bit_count(0, 4).should == 0
      "\xF0".bit_count(0, 4, lsb_first: false).should == 4
    end

    it "accepts lsb_first for a whole-string count but does not use it" do
      "\xFF".bit_count(lsb_first: false).should == 8
    end

    it "raises an ArgumentError for a lone offset without a length" do
      -> { "\x00".bit_count(0) }.should.raise(ArgumentError)
    end

    it "raises for an invalid region" do
      -> { "\x00".bit_count(-1, 4) }.should.raise(IndexError)
      -> { "\x00".bit_count(0, -1) }.should.raise(ArgumentError)
      -> { "\x00".bit_count(0, 4, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
