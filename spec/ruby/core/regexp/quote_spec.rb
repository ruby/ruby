# encoding: binary

require_relative '../../spec_helper'

describe "Regexp.quote" do
  it "escapes any characters with special meaning in a regular expression" do
    Regexp.quote('\*?{}.+^$[]()- ').should == '\\\\\*\?\{\}\.\+\^\$\[\]\(\)\-\\ '
    Regexp.quote("\*?{}.+^$[]()- ").should == '\\*\\?\\{\\}\\.\\+\\^\\$\\[\\]\\(\\)\\-\\ '
    Regexp.quote('\n\r\f\t').should == '\\\\n\\\\r\\\\f\\\\t'
    Regexp.quote("\n\r\f\t").should == '\\n\\r\\f\\t'
  end

  it "works with symbols" do
    Regexp.quote(:symbol).should == 'symbol'
  end

  it "works with substrings" do
    str = ".+[]()"[1...-1]
    Regexp.quote(str).should == '\+\[\]\('
  end

  it "works for broken strings" do
    Regexp.quote("a.\x85b.".dup.force_encoding("US-ASCII")).should =="a\\.\x85b\\.".dup.force_encoding("US-ASCII")
    Regexp.quote("a.\x80".dup.force_encoding("UTF-8")).should == "a\\.\x80".dup.force_encoding("UTF-8")
  end

  it "sets the encoding of the result to US-ASCII if there are only US-ASCII characters present in the input String" do
    str = "abc".dup.force_encoding("euc-jp")
    Regexp.quote(str).encoding.should == Encoding::US_ASCII
  end

  it "sets the encoding of the result to the encoding of the String if any non-US-ASCII characters are present in an input String with valid encoding" do
    str = "ありがとう".dup.force_encoding("utf-8")
    str.valid_encoding?.should == true
    Regexp.quote(str).encoding.should == Encoding::UTF_8
  end

  it "sets the encoding of the result to BINARY if any non-US-ASCII characters are present in an input String with invalid encoding" do
    str = "\xff".dup.force_encoding "us-ascii"
    str.valid_encoding?.should == false
    Regexp.quote("\xff").encoding.should == Encoding::BINARY
  end
end
