require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#pos" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the position of the scan pointer" do
    @s.pos.should == 0
    @s.scan_until(/This is/)
    @s.pos.should == 7
    @s.get_byte
    @s.pos.should == 8
    @s.terminate
    @s.pos.should == 14
  end

  it "returns 0 in the reset position" do
    @s.reset
    @s.pos.should == 0
  end

  it "returns the length of the string in the terminate position" do
    @s.terminate
    @s.pos.should == @s.string.length
  end

  it "is not multi-byte character sensitive" do
    s = StringScanner.new("abcädeföghi")

    s.scan_until(/ö/)
    s.pos.should == 10
  end
end

describe "StringScanner#pos=" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "modify the scan pointer" do
    @s.pos = 5
    @s.rest.should == "is a test"
  end

  it "positions from the end if the argument is negative" do
    @s.pos = -2
    @s.rest.should == "st"
    @s.pos.should == 12
  end

  it "raises a RangeError if position too far backward" do
    -> {
      @s.pos = -20
    }.should.raise(RangeError)
  end

  it "raises a RangeError when the passed argument is out of range" do
    -> { @s.pos = 20 }.should.raise(RangeError)
  end
end
