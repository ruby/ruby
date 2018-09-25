require_relative '../../../spec_helper'

with_feature :encoding do
  describe "Encoding::Converter#convpath" do
    it "returns an Array with a single element if there is a direct converter" do
      cp = Encoding::Converter.new('ASCII', 'UTF-8').convpath
      cp.should == [[Encoding::US_ASCII, Encoding::UTF_8]]
    end

    it "returns multiple encoding pairs when direct conversion is impossible" do
      cp = Encoding::Converter.new('ascii','Big5').convpath
      cp.should == [
        [Encoding::US_ASCII, Encoding::UTF_8],
        [Encoding::UTF_8, Encoding::Big5]
      ]
    end

    it "indicates if crlf_newline conversion would occur" do
      ec = Encoding::Converter.new("ISo-8859-1", "EUC-JP", {crlf_newline: true})
      ec.convpath.last.should == "crlf_newline"

      ec = Encoding::Converter.new("ASCII", "UTF-8", {crlf_newline: false})
      ec.convpath.last.should_not == "crlf_newline"
    end
  end
end
