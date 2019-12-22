require_relative '../../spec_helper'

describe "Encoding::InvalidByteSequenceError#readagain_bytes" do
  it "returns the next byte" do
    begin
      "abc\xa4def".encode("ISO-8859-1", "EUC-JP")
    rescue Encoding::InvalidByteSequenceError => e
      e.error_bytes.should == "\xA4".force_encoding("ASCII-8BIT")
      e.readagain_bytes.should == 'd'
    end
  end
end
