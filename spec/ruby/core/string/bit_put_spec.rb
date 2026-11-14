# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_put" do
    it "writes a bit in LSB-first order by default and returns self" do
      str = +"\x00"
      str.bit_put(1, 1).should.equal?(str)
      str.should == "\x02"
      str.bit_put(1, 0)
      str.should == "\x00"
    end

    it "writes a bit in MSB-first order" do
      str = +"\x00"
      str.bit_put(1, 1, lsb_first: false)
      str.should == "\x40"
    end

    it "preserves byte order when using MSB-first order" do
      str = +"\x00\x00"
      str.bit_put(8, 1, lsb_first: false)
      str.should == "\x00\x80"
    end

    it "writes an Integer into a region given as offset and length and returns self" do
      str = +"\x00\x00"
      str.bit_put(4, 8, 0xAF).should.equal?(str)
      str.should == "\xF0\x0A"
    end

    it "writes an Integer into a region given as a Range" do
      str = +"\x00\x00"
      str.bit_put(4..11, 0xAF)
      str.should == "\xF0\x0A"
      str.bit_put(8.., 0xAA)
      str.should == "\xF0\xAA"
    end

    it "leaves the bits outside the region unchanged" do
      str = +"\xFF\xFF"
      str.bit_put(4, 8, 0)
      str.should == "\x0F\xF0"
    end

    it "puts the most significant bit first in MSB-first order" do
      str = +"\x00\x00\x00\x00"
      str.bit_put(0, 16, 0x1234, lsb_first: false)
      str.bit_put(16, 16, 0x8180, lsb_first: false)
      str.should == "\x12\x34\x81\x80"
    end

    it "writes the value that String#bit_get reads" do
      str = +"\x5A\xC3\x3C"
      str.bit_put(7, 10, 0x2B5)
      str.bit_get(7, 10).should == 0x2B5
      str.bit_put(7, 10, 0x2B5, lsb_first: false)
      str.bit_get(7, 10, lsb_first: false).should == 0x2B5
    end

    it "writes a region wider than 64 bits" do
      str = +"\x00" * 11
      str.bit_put(0, 88, 1 | (1 << 87))
      str.should == "\x01" + "\x00" * 9 + "\x80"
    end

    it "writes nothing for an empty region with the value 0" do
      str = +"\xA5"
      str.bit_put(0, 0, 0).should.equal?(str)
      str.bit_put(8, 0, 0)
      str.should == "\xA5"
    end

    it "raises a RangeError for a value that does not fit in the region" do
      str = +"\x00\x00"
      -> { str.bit_put(0, 2) }.should.raise(RangeError)
      -> { str.bit_put(0, 4, 0x10) }.should.raise(RangeError)
      -> { str.bit_put(0.., 0x10000) }.should.raise(RangeError)
      -> { str.bit_put(0, 0, 1) }.should.raise(RangeError)
      str.should == "\x00\x00"
    end

    it "raises a RangeError for a negative value" do
      str = +"\x00"
      -> { str.bit_put(0, -1) }.should.raise(RangeError)
      -> { str.bit_put(0, 8, -1) }.should.raise(RangeError)
      str.should == "\x00"
    end

    it "raises an IndexError for an out of range bit offset" do
      -> { (+"\x00").bit_put(8, 1) }.should.raise(IndexError)
      -> { (+"\x00").bit_put(-1, 1) }.should.raise(IndexError)
    end

    it "raises an IndexError when a region extends past the end" do
      -> { (+"\x00").bit_put(0, 9, 0) }.should.raise(IndexError)
      -> { (+"\x00").bit_put(0..8, 0) }.should.raise(IndexError)
    end

    it "raises an ArgumentError for a negative length" do
      -> { (+"\x00").bit_put(0, -1, 0) }.should.raise(ArgumentError)
    end

    it "raises a TypeError for a value that is not an Integer" do
      -> { (+"\x00").bit_put(0, true) }.should.raise(TypeError)
      -> { (+"\x00").bit_put(0, 4, nil) }.should.raise(TypeError)
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bit_put(0, 1) }.should.raise(FrozenError)
    end

    it "raises an IndexError for a negative Range endpoint" do
      -> { (+"\x00").bit_put(-1..2, 0) }.should.raise(IndexError)
      -> { (+"\x00").bit_put(0..-1, 0) }.should.raise(IndexError)
    end

    it "writes the bytes of a region regardless of the encoding" do
      str = "a".dup.force_encoding(Encoding::UTF_8)
      str.bit_put(7, 1)
      str.encoding.should == Encoding::UTF_8
      str.b.should == "\xE1"
      str.valid_encoding?.should == false
    end
  end
end
