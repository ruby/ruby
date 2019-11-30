require_relative '../../spec_helper'

describe "Encoding::UndefinedConversionError#destination_encoding_name" do
  it "returns the destination encoding name" do
    ec = Encoding::Converter.new("ISO-8859-1", "EUC-JP")
    begin
      ec.convert("\xa0")
    rescue Encoding::UndefinedConversionError => e
      e.destination_encoding_name.should == "EUC-JP"
    end
  end
end

describe "Encoding::InvalidByteSequenceError#destination_encoding_name" do
  it "returns the destination encoding name" do
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    begin
      ec.convert("\xa0")
    rescue Encoding::InvalidByteSequenceError => e
      e.destination_encoding_name.should == "UTF-8"
    end
  end
end
