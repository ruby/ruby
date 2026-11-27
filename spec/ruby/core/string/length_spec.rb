require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#length" do
  it "returns the length of self" do
    "".length.should == 0
    "\x00".length.should == 1
    "one".length.should == 3
    "two".length.should == 3
    "three".length.should == 5
    "four".length.should == 4
  end

  it "returns the length of a string in different encodings" do
    utf8_str = 'こにちわ' * 100
    utf8_str.length.should == 400
    utf8_str.encode(Encoding::UTF_32BE).length.should == 400
    utf8_str.encode(Encoding::SHIFT_JIS).length.should == 400
  end

  it "returns the length of the new self after encoding is changed" do
    str = +'こにちわ'
    str.length

    str.force_encoding('BINARY').length.should == 12
  end

  it "returns the correct length after force_encoding(BINARY)" do
    utf8 = "あ"
    ascii = "a"
    concat = utf8 + ascii

    concat.encoding.should == Encoding::UTF_8
    concat.bytesize.should == 4

    concat.length.should == 2
    concat.force_encoding(Encoding::ASCII_8BIT)
    concat.length.should == 4
  end

  it "adds 1 for every invalid byte in UTF-8" do
    "\xF4\x90\x80\x80".length.should == 4
    "a\xF4\x90\x80\x80b".length.should == 6
    "é\xF4\x90\x80\x80è".length.should == 6
  end

  it "adds 1 (and not 2) for a incomplete surrogate in UTF-16" do
    "\x00\xd8".dup.force_encoding("UTF-16LE").length.should == 1
    "\xd8\x00".dup.force_encoding("UTF-16BE").length.should == 1
  end

  it "adds 1 for a broken sequence in UTF-32" do
    "\x04\x03\x02\x01".dup.force_encoding("UTF-32LE").length.should == 1
    "\x01\x02\x03\x04".dup.force_encoding("UTF-32BE").length.should == 1
  end
end
