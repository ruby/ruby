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
    utf8_str.size.should == 400
    utf8_str.encode(Encoding::UTF_32BE).size.should == 400
    utf8_str.encode(Encoding::SHIFT_JIS).size.should == 400
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

    concat.size.should == 2
    concat.force_encoding(Encoding::ASCII_8BIT)
    concat.size.should == 4
  end
end
