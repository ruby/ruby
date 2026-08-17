# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_set" do
    it "sets a bit in LSB-first order by default and returns self" do
      str = +"\x00"
      str.bit_set(1).should.equal?(str)
      str.should == "\x02"
    end

    it "sets a bit in MSB-first order" do
      str = +"\x00"
      str.bit_set(1, lsb_first: false)
      str.should == "\x40"
    end

    it "preserves byte order when using MSB-first order" do
      str = +"\x00\x00"
      str.bit_set(8, lsb_first: false)
      str.should == "\x00\x80"
    end

    it "sets a region given as offset and length and returns self" do
      str = +"\x00\x00"
      str.bit_set(4, 8).should.equal?(str)
      str.should == "\xF0\x0F"
    end

    it "sets a region given as a Range" do
      str = +"\x00\x00"
      str.bit_set(4..11)
      str.should == "\xF0\x0F"
    end

    it "raises an IndexError for an out of range bit offset" do
      -> { "\x00".bit_set(8) }.should.raise(IndexError)
      -> { "\x00".bit_set(-1) }.should.raise(IndexError)
    end

    it "raises an IndexError when a region extends past the end" do
      -> { "\x00".bit_set(0, 9) }.should.raise(IndexError)
      -> { "\x00".bit_set(0..8) }.should.raise(IndexError)
    end

    it "raises an ArgumentError for a negative length" do
      -> { "\x00".bit_set(0, -1) }.should.raise(ArgumentError)
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bit_set(0) }.should.raise(FrozenError)
    end
  end
end
