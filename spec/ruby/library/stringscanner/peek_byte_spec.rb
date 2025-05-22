require_relative '../../spec_helper'
require 'strscan'

version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
  describe "StringScanner#peek_byte" do
    it "returns a byte at the current position as an Integer" do
      s = StringScanner.new('This is a test')
      s.peek_byte.should == 84
    end

    it "returns nil at the end of the string" do
      s = StringScanner.new('a')
      s.getch # skip one
      s.pos.should == 1
      s.peek_byte.should == nil
    end

    it "is not multi-byte character sensitive" do
      s = StringScanner.new("∂") # "∂".bytes => [226, 136, 130]
      s.peek_byte.should == 226
      s.pos = 1
      s.peek_byte.should == 136
      s.pos = 2
      s.peek_byte.should == 130
    end

    it "doesn't change current position" do
      s = StringScanner.new('This is a test')

      s.pos.should == 0
      s.peek_byte.should == 84
      s.pos.should == 0
    end
  end
end
