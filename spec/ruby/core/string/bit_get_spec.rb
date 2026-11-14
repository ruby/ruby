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

    it "returns the bits of a region given as offset and length as an Integer" do
      data = "\xF0\xAA"
      data.bit_get(0, 8).should == 0xF0
      data.bit_get(8, 8).should == 0xAA
      data.bit_get(0, 4).should == 0x0
      data.bit_get(4, 4).should == 0xF
      data.bit_get(4, 8).should == 0xAF
      data.bit_get(0, 16).should == 0xAAF0
    end

    it "returns the bits of a region given as a Range as an Integer" do
      data = "\xF0\xAA"
      data.bit_get(0..7).should == 0xF0
      data.bit_get(8..).should == 0xAA
      data.bit_get(nil..nil).should == 0xAAF0
    end

    it "makes the first bit of a region the most significant bit in MSB-first order" do
      hdr = "\x12\x34\x81\x80"
      hdr.bit_get(0, 16, lsb_first: false).should == 0x1234
      hdr.bit_get(4, 12, lsb_first: false).should == 0x234
      hdr.bit_get(0, 16).should == 0x3412
    end

    it "returns a region wider than 64 bits" do
      wide = "\x01" + "\x00" * 9 + "\x80"
      wide.bit_get(0, 88).should == (1 | (1 << 87))
      wide.bit_get(0, 88, lsb_first: false).should == ((1 << 80) | (1 << 7))
    end

    it "returns nil for a region that extends past the end of the string" do
      data = "\xF0\xAA"
      data.bit_get(8, 9).should == nil
      data.bit_get(8..16).should == nil
      data.bit_get(16, 1).should == nil
    end

    it "returns 0 for an empty region unless it begins beyond the end of the string" do
      data = "\xF0\xAA"
      data.bit_get(16, 0).should == 0
      data.bit_get(5..2).should == 0
      data.bit_get(17, 0).should == nil
    end

    it "raises an IndexError for a negative bit offset" do
      -> { "\x00".bit_get(-1) }.should.raise(IndexError)
      -> { "\x00".bit_get(-1, 4) }.should.raise(IndexError)
    end

    it "raises an ArgumentError for a negative length" do
      -> { "\x00".bit_get(0, -1) }.should.raise(ArgumentError)
    end

    it "raises an ArgumentError for a Range with a length" do
      -> { "\x00".bit_get(0..3, 4) }.should.raise(ArgumentError)
    end

    it "raises an ArgumentError for an invalid lsb_first value" do
      -> { "\x00".bit_get(0, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
