require_relative '../../spec_helper'

describe "Encoding::InvalidByteSequenceError#error_bytes" do
  it "returns the error bytes" do
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    begin
      ec.convert("\xa0")
    rescue Encoding::InvalidByteSequenceError => e
      e.error_bytes.should == "\xA0".force_encoding("ASCII-8BIT")
    end
  end
end
