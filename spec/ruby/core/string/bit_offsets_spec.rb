# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_offsets" do
    it "returns the offsets of the set bits for bit = 1 in LSB-first order by default" do
      "\xAA\xCC".bit_offsets(1).should == [1, 3, 5, 7, 10, 11, 14, 15]
    end

    it "returns the offsets of the cleared bits for bit = 0" do
      "\xAA\xCC".bit_offsets(0).should == [0, 2, 4, 6, 8, 9, 12, 13]
    end

    it "returns offsets in MSB-first order when lsb_first is false" do
      "\xAA\xCC".bit_offsets(1, lsb_first: false).should == [0, 2, 4, 6, 8, 9, 12, 13]
    end

    it "scans a region" do
      "\xAA\xCC".bit_offsets(1, 8, 4).should == [10, 11]
    end

    it "clamps a region that extends past the end of the string" do
      "\xAA\xCC".bit_offsets(1, 12, 100).should == [14, 15]
      "\xAA\xCC".bit_offsets(1, 100, 8).should == []
    end

    it "returns an empty Array for an empty string" do
      "".bit_offsets(1).should == []
    end

    it "yields each offset and returns self when a block is given" do
      str = "\xAA"
      offsets = []
      str.bit_offsets(1) { |i| offsets << i }.should equal(str)
      offsets.should == [1, 3, 5, 7]
    end

    it "raises for an invalid bit value" do
      -> { "\x00".bit_offsets(2) }.should.raise(ArgumentError)
      -> { "\x00".bit_offsets(nil) }.should.raise(TypeError)
    end

    it "raises an ArgumentError for a lone offset without a length" do
      -> { "\x00".bit_offsets(1, 0) }.should.raise(ArgumentError)
    end
  end
end
