# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#each_bit" do
    it "yields each bit as 0 or 1 in LSB-first order by default" do
      bits = []
      "\xAA".each_bit { |bit| bits << bit }
      bits.should == [0, 1, 0, 1, 0, 1, 0, 1]
    end

    it "yields each bit in MSB-first order when lsb_first is false" do
      "\xAA".each_bit(lsb_first: false).to_a.should == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    it "returns self when a block is given" do
      str = "\xAA"
      str.each_bit { }.should equal(str)
    end

    it "returns a sized Enumerator when no block is given" do
      enum = "\xFF\xAA".each_bit
      enum.should be_an_instance_of(Enumerator)
      enum.size.should == 16
      "\xFF\xAA".each_bit(8, 4).size.should == 4
    end

    it "iterates over a region given as offset and length" do
      "\xFF\xAA".each_bit(8, 4).to_a.should == [0, 1, 0, 1]
    end

    it "iterates over a region given as a Range" do
      "\xFF\xAA".each_bit(8..).to_a.should == [0, 1, 0, 1, 0, 1, 0, 1]
      "\xFF\xAA".each_bit(8...12).to_a.should == [0, 1, 0, 1]
    end

    it "clamps a region that extends past the end of the string" do
      "\xFF\xAA".each_bit(12, 100).to_a.should == [0, 1, 0, 1]
      "\xFF\xAA".each_bit(100, 8).to_a.should == []
    end

    it "yields nothing for an empty string" do
      "".each_bit.to_a.should == []
    end

    it "stops at the new end when the block shrinks the string" do
      str = "\xFF\xFF\xFF\xFF"
      bits = []
      str.each_bit { |bit| bits << bit; str.replace("\x0F") if bits.size == 2 }
      bits.should == [1, 1, 1, 1, 0, 0, 0, 0]
    end

    it "raises an ArgumentError for a lone offset without a length" do
      -> { "\x00".each_bit(0) }.should.raise(ArgumentError)
    end

    it "raises for an invalid region" do
      -> { "\x00".each_bit(-1, 4) }.should.raise(IndexError)
      -> { "\x00".each_bit(-1..3) }.should.raise(IndexError)
      -> { "\x00".each_bit(0, -1) }.should.raise(ArgumentError)
      -> { "\x00".each_bit(0..3, 4) }.should.raise(ArgumentError)
    end

    it "raises an ArgumentError for an invalid lsb_first value" do
      -> { "\x00".each_bit(lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
