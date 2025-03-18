require 'stringio'
require_relative '../../spec_helper'

# Should be synced with specs for IO#set_encoding_by_bom
describe "StringIO#set_encoding_by_bom" do
  it "returns nil if not readable" do
    io = StringIO.new("".b, "wb")

    io.set_encoding_by_bom.should be_nil
    io.external_encoding.should == Encoding::ASCII_8BIT
  end

  it "returns the result encoding if found BOM UTF-8 sequence" do
    io = StringIO.new("\u{FEFF}".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_8
    io.external_encoding.should == Encoding::UTF_8
    io.read.b.should == "".b

    io = StringIO.new("\u{FEFF}abc".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_8
    io.external_encoding.should == Encoding::UTF_8
    io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_16LE sequence" do
    io = StringIO.new("\xFF\xFE".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16LE
    io.external_encoding.should == Encoding::UTF_16LE
    io.read.b.should == "".b

    io = StringIO.new("\xFF\xFEabc".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16LE
    io.external_encoding.should == Encoding::UTF_16LE
    io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_16BE sequence" do
    io = StringIO.new("\xFE\xFF".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16BE
    io.external_encoding.should == Encoding::UTF_16BE
    io.read.b.should == "".b

    io = StringIO.new("\xFE\xFFabc".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16BE
    io.external_encoding.should == Encoding::UTF_16BE
    io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_32LE sequence" do
    io = StringIO.new("\xFF\xFE\x00\x00".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_32LE
    io.external_encoding.should == Encoding::UTF_32LE
    io.read.b.should == "".b

    io = StringIO.new("\xFF\xFE\x00\x00abc".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_32LE
    io.external_encoding.should == Encoding::UTF_32LE
    io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_32BE sequence" do
    io = StringIO.new("\x00\x00\xFE\xFF".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_32BE
    io.external_encoding.should == Encoding::UTF_32BE
    io.read.b.should == "".b

    io = StringIO.new("\x00\x00\xFE\xFFabc".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_32BE
    io.external_encoding.should == Encoding::UTF_32BE
    io.read.b.should == "abc".b
  end

  it "returns nil if io is empty" do
    io = StringIO.new("".b, "rb")
    io.set_encoding_by_bom.should be_nil
    io.external_encoding.should == Encoding::ASCII_8BIT
  end

  it "returns nil if UTF-8 BOM sequence is incomplete" do
    io = StringIO.new("\xEF".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xEF".b

    io = StringIO.new("\xEFa".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xEFa".b

    io = StringIO.new("\xEF\xBB".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xEF\xBB".b

    io = StringIO.new("\xEF\xBBa".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xEF\xBBa".b
  end

  it "returns nil if UTF-16BE BOM sequence is incomplete" do
    io = StringIO.new("\xFE".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xFE".b

    io = StringIO.new("\xFEa".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xFEa".b
  end

  it "returns nil if UTF-16LE/UTF-32LE BOM sequence is incomplete" do
    io = StringIO.new("\xFF".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xFF".b

    io = StringIO.new("\xFFa".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\xFFa".b
  end

  it "returns UTF-16LE if UTF-32LE BOM sequence is incomplete" do
    io = StringIO.new("\xFF\xFE".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16LE
    io.external_encoding.should == Encoding::UTF_16LE
    io.read.b.should == "".b

    io = StringIO.new("\xFF\xFE\x00".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16LE
    io.external_encoding.should == Encoding::UTF_16LE
    io.read.b.should == "\x00".b

    io = StringIO.new("\xFF\xFE\x00a".b, "rb")

    io.set_encoding_by_bom.should == Encoding::UTF_16LE
    io.external_encoding.should == Encoding::UTF_16LE
    io.read.b.should == "\x00a".b
  end

  it "returns nil if UTF-32BE BOM sequence is incomplete" do
    io = StringIO.new("\x00".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00".b

    io = StringIO.new("\x00a".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00a".b

    io = StringIO.new("\x00\x00".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00\x00".b

    io = StringIO.new("\x00\x00a".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00\x00a".b

    io = StringIO.new("\x00\x00\xFE".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00\x00\xFE".b

    io = StringIO.new("\x00\x00\xFEa".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read.b.should == "\x00\x00\xFEa".b
  end

  it "returns nil if found BOM sequence not provided" do
    io = StringIO.new("abc".b, "rb")

    io.set_encoding_by_bom.should == nil
    io.external_encoding.should == Encoding::ASCII_8BIT
    io.read(3).should == "abc".b
  end

  it "does not raise exception if io not in binary mode" do
    io = StringIO.new("", 'r')
    io.set_encoding_by_bom.should == nil
  end

  it "does not raise exception if encoding already set" do
    io = StringIO.new("".b, "rb")
    io.set_encoding("utf-8")
    io.set_encoding_by_bom.should == nil
  end

  it "does not raise exception if encoding conversion is already set" do
    io = StringIO.new("".b, "rb")
    io.set_encoding(Encoding::UTF_8, Encoding::UTF_16BE)

    io.set_encoding_by_bom.should == nil
  end

  it "raises FrozenError when io is frozen" do
    io = StringIO.new()
    io.freeze
    -> { io.set_encoding_by_bom }.should raise_error(FrozenError)
  end

  it "does not raise FrozenError when initial string is frozen" do
    io = StringIO.new("".freeze)
    io.set_encoding_by_bom.should == nil
  end
end
