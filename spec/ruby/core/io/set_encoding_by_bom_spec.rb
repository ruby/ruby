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

  ruby_version_is "2.7" do
    it "returns the result encoding if found BOM UTF-8 sequence" do
      File.binwrite(@name, "\u{FEFF}abc")

      @io.set_encoding_by_bom.should == Encoding::UTF_8
      @io.external_encoding.should == Encoding::UTF_8
    end

    it "returns the result encoding if found BOM UTF_16LE sequence" do
      File.binwrite(@name, "\xFF\xFEabc")

      @io.set_encoding_by_bom.should == Encoding::UTF_16LE
      @io.external_encoding.should == Encoding::UTF_16LE
    end

    it "returns the result encoding if found BOM UTF_16BE sequence" do
      File.binwrite(@name, "\xFE\xFFabc")

      @io.set_encoding_by_bom.should == Encoding::UTF_16BE
      @io.external_encoding.should == Encoding::UTF_16BE
    end

    it "returns the result encoding if found BOM UTF_32LE sequence" do
      File.binwrite(@name, "\xFF\xFE\x00\x00abc")

      @io.set_encoding_by_bom.should == Encoding::UTF_32LE
      @io.external_encoding.should == Encoding::UTF_32LE
    end

    it "returns the result encoding if found BOM UTF_32BE sequence" do
      File.binwrite(@name, "\x00\x00\xFE\xFFabc")

      @io.set_encoding_by_bom.should == Encoding::UTF_32BE
      @io.external_encoding.should == Encoding::UTF_32BE
    end

    it "returns nil if found BOM sequence not provided" do
      File.write(@name, "abc")

      @io.set_encoding_by_bom.should == nil
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
end
