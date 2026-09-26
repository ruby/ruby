# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#each_bit_offset" do
    it "yields the offset of each set bit for bit = 1 in LSB-first order by default" do
      offsets = []
      "\xAA\xCC".each_bit_offset(1) { |offset| offsets << offset }
      offsets.should == [1, 3, 5, 7, 10, 11, 14, 15]
    end

    it "yields the offset of each cleared bit for bit = 0" do
      "\xAA\xCC".each_bit_offset(0).to_a.should == [0, 2, 4, 6, 8, 9, 12, 13]
    end

    it "accepts true and false as the bit value" do
      "\xAA\xCC".each_bit_offset(true).to_a.should == [1, 3, 5, 7, 10, 11, 14, 15]
      "\xAA\xCC".each_bit_offset(false).to_a.should == [0, 2, 4, 6, 8, 9, 12, 13]
    end

    it "yields offsets in MSB-first order when lsb_first is false" do
      "\xAA\xCC".each_bit_offset(1, lsb_first: false).to_a.should == [0, 2, 4, 6, 8, 9, 12, 13]
    end

    it "yields offsets that agree with bit_set? under the same numbering" do
      str = "\xAA\xCC"
      str.each_bit_offset(1, lsb_first: false).all? { |i| str.bit_set?(i, lsb_first: false) }.should == true
      str.each_bit_offset(0).none? { |i| str.bit_set?(i) }.should == true
    end

    it "returns self when a block is given" do
      str = "\xAA"
      str.each_bit_offset(1) { }.should equal(str)
    end

    it "returns a sized Enumerator when no block is given" do
      enum = "\xAA\xCC".each_bit_offset(1)
      enum.should be_an_instance_of(Enumerator)
      enum.size.should == 8
      "\xAA\xCC".each_bit_offset(0, 4..11).size.should == 4
    end

    it "scans a region given as offset and length and yields absolute offsets" do
      "\xAA\xCC".each_bit_offset(1, 8, 4).to_a.should == [10, 11]
    end

    it "scans a region given as a Range" do
      "\xAA\xCC".each_bit_offset(1, 8..).to_a.should == [10, 11, 14, 15]
      "\xAA\xCC".each_bit_offset(1, 4...12).to_a.should == [5, 7, 10, 11]
    end

    it "clamps a region that extends past the end of the string" do
      "\xAA\xCC".each_bit_offset(1, 12, 100).to_a.should == [14, 15]
      "\xAA\xCC".each_bit_offset(1, 100, 8).to_a.should == []
    end

    it "yields nothing for an empty string" do
      "".each_bit_offset(1).to_a.should == []
    end

    it "stops at the new end when the block shrinks the string" do
      str = "\xFF\xFF\xFF\xFF"
      offsets = []
      str.each_bit_offset(1) { |i| offsets << i; str.replace("\x00") if offsets.size == 3 }
      offsets.should == [0, 1, 2]
    end

    it "raises an ArgumentError for an Integer bit other than 0 or 1" do
      -> { "\x00".each_bit_offset(2) }.should.raise(ArgumentError)
    end

    it "raises a TypeError for a bit that is not an Integer or a boolean" do
      -> { "\x00".each_bit_offset(nil) }.should.raise(TypeError)
      -> { "\x00".each_bit_offset("1") }.should.raise(TypeError)
    end

    it "raises an ArgumentError for a lone offset without a length" do
      -> { "\x00".each_bit_offset(1, 0) }.should.raise(ArgumentError)
    end

    it "raises for an invalid region" do
      -> { "\x00".each_bit_offset(1, -1, 4) }.should.raise(IndexError)
      -> { "\x00".each_bit_offset(1, 0, -1) }.should.raise(ArgumentError)
      -> { "\x00".each_bit_offset(1, 0..3, 4) }.should.raise(ArgumentError)
      -> { "\x00".each_bit_offset(1, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
