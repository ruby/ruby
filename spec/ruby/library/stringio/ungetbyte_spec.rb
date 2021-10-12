# frozen_string_literal: false
require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#ungetbyte" do
  it "ungets a single byte from a string starting with a single byte character" do
    str = 'This is a simple string.'
    io = StringIO.new("#{str}")
    c = io.getc
    c.should == 'T'
    io.ungetbyte(83)
    io.string.should == 'Shis is a simple string.'
  end

  it "ungets a single byte from a string in the middle of a multibyte characte" do
    str = "\u01a9"
    io = StringIO.new(str)
    b = io.getbyte
    b.should == 0xc6 # First byte of UTF-8 encoding of \u01a9
    io.ungetbyte(0xce) # First byte of UTF-8 encoding of \u03a9
    io.string.should == "\u03a9"
  end

  it "constrains the value of a numeric argument to a single byte" do
    str = 'This is a simple string.'
    io = StringIO.new("#{str}")
    c = io.getc
    c.should == 'T'
    io.ungetbyte(83 | 0xff00)
    io.string.should == 'Shis is a simple string.'
  end

  it "ungets the bytes of a string if given a string as an arugment" do
    str = "\u01a9"
    io = StringIO.new(str)
    b = io.getbyte
    b.should == 0xc6 # First byte of UTF-8 encoding of \u01a9
    io.ungetbyte("\u01a9")
    io.string.bytes.should == [198, 169, 169]
  end

end
