# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_clear" do
    it "clears a bit in LSB-first order by default and returns self" do
      str = "\xFF".dup
      str.bit_clear(1).should.equal?(str)
      str.should == "\xFD"
    end

    it "clears a bit in MSB-first order" do
      str = "\xFF".dup
      str.bit_clear(1, lsb_first: false)
      str.should == "\xBF"
    end

    it "preserves byte order when using MSB-first order" do
      str = "\xFF\xFF".dup
      str.bit_clear(8, lsb_first: false)
      str.should == "\xFF\x7F"
    end

    it "raises an IndexError for an out of range bit offset" do
      -> { "\x00".bit_clear(8) }.should.raise(IndexError)
      -> { "\x00".bit_clear(-1) }.should.raise(IndexError)
    end

    it "raises a FrozenError if self is frozen" do
      -> { "\x00".freeze.bit_clear(0) }.should.raise(FrozenError)
    end
  end
end
