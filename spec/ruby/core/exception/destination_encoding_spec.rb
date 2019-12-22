require_relative '../../spec_helper'

describe "Encoding::UndefinedConversionError#destination_encoding" do
  it "returns the destination encoding" do
    ec = Encoding::Converter.new("ISO-8859-1", "EUC-JP")
    begin
      ec.convert("\xa0")
    rescue Encoding::UndefinedConversionError => e
      e.destination_encoding.should == Encoding::EUC_JP
    end
  end
end

describe "Encoding::InvalidByteSequenceError#destination_encoding" do
  it "returns the destination encoding" do
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    begin
      ec.convert("\xa0")
    rescue Encoding::InvalidByteSequenceError => e
      e.destination_encoding.should == Encoding::UTF_8
    end
  end
end
