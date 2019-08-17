require_relative '../../../spec_helper'

describe "Encoding::Converter#source_encoding" do
  it "returns the source encoding as an Encoding object" do
    ec = Encoding::Converter.new('ASCII','Big5')
    ec.source_encoding.should == Encoding::US_ASCII

    ec = Encoding::Converter.new('Shift_JIS','EUC-JP')
    ec.source_encoding.should == Encoding::SHIFT_JIS
  end
end
