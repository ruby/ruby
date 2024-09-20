require_relative '../../spec_helper'

describe "IO#set_encoding_by_bom" do
  before :each do
    @name = tmp('io_set_encoding_by_bom.txt')
    touch(@name)
    @io = new_io(@name, 'rb')
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  it "returns nil if not readable" do
    not_readable_io = new_io(@name, 'wb')

    not_readable_io.set_encoding_by_bom.should be_nil
    not_readable_io.external_encoding.should == Encoding::ASCII_8BIT
  ensure
    not_readable_io.close
  end

  it "returns the result encoding if found BOM UTF-8 sequence" do
    File.binwrite(@name, "\u{FEFF}")

    @io.set_encoding_by_bom.should == Encoding::UTF_8
    @io.external_encoding.should == Encoding::UTF_8
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.binwrite(@name, "\u{FEFF}abc")

    @io.set_encoding_by_bom.should == Encoding::UTF_8
    @io.external_encoding.should == Encoding::UTF_8
    @io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_16LE sequence" do
    File.binwrite(@name, "\xFF\xFE")

    @io.set_encoding_by_bom.should == Encoding::UTF_16LE
    @io.external_encoding.should == Encoding::UTF_16LE
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.binwrite(@name, "\xFF\xFEabc")

    @io.set_encoding_by_bom.should == Encoding::UTF_16LE
    @io.external_encoding.should == Encoding::UTF_16LE
    @io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_16BE sequence" do
    File.binwrite(@name, "\xFE\xFF")

    @io.set_encoding_by_bom.should == Encoding::UTF_16BE
    @io.external_encoding.should == Encoding::UTF_16BE
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.binwrite(@name, "\xFE\xFFabc")

    @io.set_encoding_by_bom.should == Encoding::UTF_16BE
    @io.external_encoding.should == Encoding::UTF_16BE
    @io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_32LE sequence" do
    File.binwrite(@name, "\xFF\xFE\x00\x00")

    @io.set_encoding_by_bom.should == Encoding::UTF_32LE
    @io.external_encoding.should == Encoding::UTF_32LE
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.binwrite(@name, "\xFF\xFE\x00\x00abc")

    @io.set_encoding_by_bom.should == Encoding::UTF_32LE
    @io.external_encoding.should == Encoding::UTF_32LE
    @io.read.b.should == "abc".b
  end

  it "returns the result encoding if found BOM UTF_32BE sequence" do
    File.binwrite(@name, "\x00\x00\xFE\xFF")

    @io.set_encoding_by_bom.should == Encoding::UTF_32BE
    @io.external_encoding.should == Encoding::UTF_32BE
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.binwrite(@name, "\x00\x00\xFE\xFFabc")

    @io.set_encoding_by_bom.should == Encoding::UTF_32BE
    @io.external_encoding.should == Encoding::UTF_32BE
    @io.read.b.should == "abc".b
  end

  it "returns nil if io is empty" do
    @io.set_encoding_by_bom.should be_nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
  end

  it "returns nil if UTF-8 BOM sequence is incomplete" do
    File.write(@name, "\xEF")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xEF".b
    @io.rewind

    File.write(@name, "\xEFa")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xEFa".b
    @io.rewind

    File.write(@name, "\xEF\xBB")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xEF\xBB".b
    @io.rewind

    File.write(@name, "\xEF\xBBa")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xEF\xBBa".b
  end

  it "returns nil if UTF-16BE BOM sequence is incomplete" do
    File.write(@name, "\xFE")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xFE".b
    @io.rewind

    File.write(@name, "\xFEa")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xFEa".b
  end

  it "returns nil if UTF-16LE/UTF-32LE BOM sequence is incomplete" do
    File.write(@name, "\xFF")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xFF".b
    @io.rewind

    File.write(@name, "\xFFa")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\xFFa".b
  end

  it "returns UTF-16LE if UTF-32LE BOM sequence is incomplete" do
    File.write(@name, "\xFF\xFE")

    @io.set_encoding_by_bom.should == Encoding::UTF_16LE
    @io.external_encoding.should == Encoding::UTF_16LE
    @io.read.b.should == "".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.write(@name, "\xFF\xFE\x00")

    @io.set_encoding_by_bom.should == Encoding::UTF_16LE
    @io.external_encoding.should == Encoding::UTF_16LE
    @io.read.b.should == "\x00".b
    @io.rewind
    @io.set_encoding(Encoding::ASCII_8BIT)

    File.write(@name, "\xFF\xFE\x00a")

    @io.set_encoding_by_bom.should == Encoding::UTF_16LE
    @io.external_encoding.should == Encoding::UTF_16LE
    @io.read.b.should == "\x00a".b
  end

  it "returns nil if UTF-32BE BOM sequence is incomplete" do
    File.write(@name, "\x00")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00".b
    @io.rewind

    File.write(@name, "\x00a")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00a".b
    @io.rewind

    File.write(@name, "\x00\x00")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00\x00".b
    @io.rewind

    File.write(@name, "\x00\x00a")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00\x00a".b
    @io.rewind

    File.write(@name, "\x00\x00\xFE")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00\x00\xFE".b
    @io.rewind

    File.write(@name, "\x00\x00\xFEa")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read.b.should == "\x00\x00\xFEa".b
  end

  it "returns nil if found BOM sequence not provided" do
    File.write(@name, "abc")

    @io.set_encoding_by_bom.should == nil
    @io.external_encoding.should == Encoding::ASCII_8BIT
    @io.read(3).should == "abc".b
  end

  it 'returns exception if io not in binary mode' do
    not_binary_io = new_io(@name, 'r')

    -> { not_binary_io.set_encoding_by_bom }.should raise_error(ArgumentError, 'ASCII incompatible encoding needs binmode')
  ensure
    not_binary_io.close
  end

  it 'returns exception if encoding already set' do
    @io.set_encoding("utf-8")

    -> { @io.set_encoding_by_bom }.should raise_error(ArgumentError, 'encoding is set to UTF-8 already')
  end

  it 'returns exception if encoding conversion is already set' do
    @io.set_encoding(Encoding::UTF_8, Encoding::UTF_16BE)

    -> { @io.set_encoding_by_bom }.should raise_error(ArgumentError, 'encoding conversion is set')
  end
end
