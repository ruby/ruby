# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bits" do
    it "returns an Array of the bits as 0 or 1 in LSB-first order by default" do
      "\xAA".bits.should == [0, 1, 0, 1, 0, 1, 0, 1]
    end

    it "returns the bits in MSB-first order when lsb_first is false" do
      "\xAA".bits(lsb_first: false).should == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    it "returns the bits of a region" do
      "\xFF\xAA".bits(8, 4).should == [0, 1, 0, 1]
    end

    it "clamps a region that extends past the end of the string" do
      "\xFF\xAA".bits(12, 100).should == [0, 1, 0, 1]
      "\xFF\xAA".bits(100, 8).should == []
    end

    it "returns an empty Array for an empty string" do
      "".bits.should == []
    end

    it "yields each bit and returns self when a block is given" do
      str = "\xAA"
      bits = []
      str.bits { |bit| bits << bit }.should equal(str)
      bits.should == [0, 1, 0, 1, 0, 1, 0, 1]
    end

    it "raises an ArgumentError for a lone offset without a length" do
      -> { "\x00".bits(0) }.should.raise(ArgumentError)
    end
  end
end
