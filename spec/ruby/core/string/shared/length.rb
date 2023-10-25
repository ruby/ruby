# encoding: utf-8

describe :string_length, shared: true do
  it "returns the length of self" do
    "".send(@method).should == 0
    "\x00".send(@method).should == 1
    "one".send(@method).should == 3
    "two".send(@method).should == 3
    "three".send(@method).should == 5
    "four".send(@method).should == 4
  end

  it "returns the length of a string in different encodings" do
    utf8_str = 'こにちわ' * 100
    utf8_str.send(@method).should == 400
    utf8_str.encode(Encoding::UTF_32BE).send(@method).should == 400
    utf8_str.encode(Encoding::SHIFT_JIS).send(@method).should == 400
  end

  it "returns the length of the new self after encoding is changed" do
    str = 'こにちわ'
    str.send(@method)

    str.force_encoding('BINARY').send(@method).should == 12
  end

  it "returns the correct length after force_encoding(BINARY)" do
    utf8 = "あ"
    ascii = "a"
    concat = utf8 + ascii

    concat.encoding.should == Encoding::UTF_8
    concat.bytesize.should == 4

    concat.send(@method).should == 2
    concat.force_encoding(Encoding::ASCII_8BIT)
    concat.send(@method).should == 4
  end

  it "adds 1 for every invalid byte in UTF-8" do
    "\xF4\x90\x80\x80".send(@method).should == 4
    "a\xF4\x90\x80\x80b".send(@method).should == 6
    "é\xF4\x90\x80\x80è".send(@method).should == 6
  end

  it "adds 1 (and not 2) for a incomplete surrogate in UTF-16" do
    "\x00\xd8".force_encoding("UTF-16LE").send(@method).should == 1
    "\xd8\x00".force_encoding("UTF-16BE").send(@method).should == 1
  end

  it "adds 1 for a broken sequence in UTF-32" do
    "\x04\x03\x02\x01".force_encoding("UTF-32LE").send(@method).should == 1
    "\x01\x02\x03\x04".force_encoding("UTF-32BE").send(@method).should == 1
  end
end
