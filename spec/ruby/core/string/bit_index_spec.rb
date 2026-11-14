# encoding: binary
require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "String#bit_index" do
    it "returns the offset of the first bit that is equal to the given bit" do
      "\xF0".bit_index(1).should == 4
      "\xF0".bit_index(0).should == 0
    end

    it "returns nil if there is no such bit" do
      "\x00".bit_index(1).should == nil
      "\xFF".bit_index(0).should == nil
      "".bit_index(1).should == nil
    end

    it "starts the search at the given offset and returns an offset from the start of the string" do
      "\xF0".bit_index(1, 5).should == 5
      "\xF0".bit_index(0, 4).should == nil
    end

    it "returns nil for an offset at or beyond the end of the string" do
      "\xF0".bit_index(1, 8).should == nil
    end

    it "searches a window given as offset and length" do
      "\xF0".bit_index(1, 0, 5).should == 4
      "\xF0".bit_index(1, 0, 4).should == nil
    end

    it "searches a window given as a Range" do
      "\xF0".bit_index(1, 0..4).should == 4
      "\xF0".bit_index(1, 0...4).should == nil
      "\xFD\x03".bit_index(0, 2..).should == 10
    end

    it "clamps a window that extends past the end of the string" do
      "\xF0".bit_index(1, 7, 100).should == 7
      "\xF0".bit_index(1, 7..100).should == 7
      "\xF0".bit_index(1, 8, 100).should == nil
    end

    it "returns nil for an empty window" do
      "\xF0".bit_index(1, 4, 0).should == nil
      "\xF0".bit_index(1, 4...4).should == nil
      "\xF0".bit_index(1, 5..4).should == nil
    end

    it "finds a bit beyond bytes that hold no matching bit" do
      ("\x00" * 100 + "\x40").bit_index(1).should == 806
      ("\xFF" * 100 + "\xBF").bit_index(0).should == 806
    end

    it "numbers the bits within each byte from the MSB when lsb_first is false" do
      "\xF0".bit_index(1, lsb_first: false).should == 0
      "\xF0".bit_index(0, lsb_first: false).should == 4
      "\xF0".bit_index(0, 0...4, lsb_first: false).should == nil
      ("\x00" * 100 + "\x40").bit_index(1, lsb_first: false).should == 801
    end

    it "works on a frozen string" do
      "\xF0".freeze.bit_index(1).should == 4
    end

    it "raises an ArgumentError for an Integer bit other than 0 or 1" do
      -> { "\xF0".bit_index(2) }.should.raise(ArgumentError)
      -> { "\xF0".bit_index(-1) }.should.raise(ArgumentError)
    end

    it "raises a TypeError for a bit that is not an Integer" do
      -> { "\xF0".bit_index(true) }.should.raise(TypeError)
      -> { "\xF0".bit_index(false) }.should.raise(TypeError)
      -> { "\xF0".bit_index(nil) }.should.raise(TypeError)
    end

    it "raises for an invalid window" do
      -> { "\xF0".bit_index(1, -1) }.should.raise(IndexError)
      -> { "\xF0".bit_index(1, 0, -1) }.should.raise(ArgumentError)
      -> { "\xF0".bit_index(1, 0..4, 1) }.should.raise(ArgumentError)
      -> { "\xF0".bit_index(1, lsb_first: nil) }.should.raise(ArgumentError)
    end
  end
end
