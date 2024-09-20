require_relative '../../spec_helper'

describe "String#ord" do
  it "returns an Integer" do
    'a'.ord.should be_an_instance_of(Integer)
  end

  it "returns the codepoint of the first character in the String" do
    'a'.ord.should == 97
  end


  it "ignores subsequent characters" do
    "\u{287}a".ord.should == "\u{287}".ord
  end

  it "understands multibyte characters" do
    "\u{9879}".ord.should == 39033
  end

  it "is equivalent to #codepoints.first" do
    "\u{981}\u{982}".ord.should == "\u{981}\u{982}".codepoints.first
  end

  it "raises an ArgumentError if called on an empty String" do
    -> { ''.ord }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the character is broken" do
    s = "©".dup.force_encoding("US-ASCII")
    -> { s.ord }.should raise_error(ArgumentError, "invalid byte sequence in US-ASCII")
  end
end
