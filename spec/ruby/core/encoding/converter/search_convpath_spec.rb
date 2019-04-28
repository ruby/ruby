require_relative '../../../spec_helper'

describe "Encoding::Converter.search_convpath" do
  it "returns an Array with a single element if there is a direct converter" do
    cp = Encoding::Converter.search_convpath('ASCII', 'UTF-8')
    cp.should == [[Encoding::US_ASCII, Encoding::UTF_8]]
  end

  it "returns multiple encoding pairs when direct conversion is impossible" do
    cp = Encoding::Converter.search_convpath('ascii','Big5')
    cp.should == [
      [Encoding::US_ASCII, Encoding::UTF_8],
      [Encoding::UTF_8, Encoding::Big5]
    ]
  end

  it "indicates if crlf_newline conversion would occur" do
    cp = Encoding::Converter.search_convpath(
      "ISO-8859-1", "EUC-JP", {crlf_newline: true})
    cp.last.should == "crlf_newline"

    cp = Encoding::Converter.search_convpath(
      "ASCII", "UTF-8", {crlf_newline: false})
    cp.last.should_not == "crlf_newline"
  end

  it "raises an Encoding::ConverterNotFoundError if no conversion path exists" do
   lambda do
     Encoding::Converter.search_convpath(Encoding::ASCII_8BIT, Encoding::Emacs_Mule)
   end.should raise_error(Encoding::ConverterNotFoundError)
  end
end
