require_relative '../../spec_helper'

describe "Encoding::UndefinedConversionError#error_char" do
  it "returns the error char" do
    ec = Encoding::Converter.new("ISO-8859-1", "EUC-JP")
    begin
      ec.convert("\xa0")
    rescue Encoding::UndefinedConversionError => e
      e.error_char.should == "\u00A0"
    end
  end
end
