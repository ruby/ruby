# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_flip" do
    it "flips a bit in LSB-first order by default and returns self" do
      str = "\x00".dup
      str.bit_flip(1).should.equal?(str)
      str.should == "\x02"
      str.bit_flip(1)
      str.should == "\x00"
    end

    it "flips a bit in MSB-first order" do
      str = "\x00".dup
      str.bit_flip(1, lsb_first: false)
      str.should == "\x40"
    end

    it "preserves byte order when using MSB-first order" do
      str = "\x00\x00".dup
      str.bit_flip(8, lsb_first: false)
      str.should == "\x00\x80"
    end

    it "raises an IndexError for an out of range bit offset" do
      -> { "\x00".bit_flip(8) }.should.raise(IndexError)
      -> { "\x00".bit_flip(-1) }.should.raise(IndexError)
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bit_flip(0) }.should.raise(FrozenError)
    end
  end
end
